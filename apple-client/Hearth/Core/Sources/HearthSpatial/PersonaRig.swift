//
//  PersonaRig.swift
//  HearthSpatial
//
//  The persona as a glowing bead in an orbiting particle field -- Sulivan's
//  `sphere_particle` visualization, and the RealityKit counterpart of the flat
//  PersonaOrb the phone draws in a SwiftUI Canvas. Particles sit on a
//  deterministic Fibonacci shell, the field spins and swells with motion, and
//  the bead breathes and glows. State drives colour, brightness, spin and
//  swell.
//
//  Ported from Valinor's RealityKitSceneManager, which was device-validated on
//  the volumetric path. Four things changed on the way, and each is a decision
//  rather than a tidy-up:
//
//    - The caustic swirl overlay is GONE, along with `sphereCausticTexture`.
//      The caustics set is `excluded` in the manifest because it was never
//      validated on a device, and an overlay whose only input is an excluded
//      texture is dead weight. Phase 2's face borrows the LowLevelTexture
//      PATTERN from that work and never its files.
//    - `PersonaState` replaces the raw turn state at this boundary. The rig
//      does not import a state machine; it is told how to look.
//    - The name. A "scene manager" that owns no scene was always a misnomer:
//      the hosts are the scenes and this is the thing they stage. Design
//      section 1's one-scene rule depends on that distinction holding.
//    - It builds for iOS as well as visionOS. The one place the platforms
//      genuinely diverge is the camera, below.
//
//  What deliberately SURVIVED the port, against the manifest's older note that
//  the mode switch should be dropped: `realBloomActive`, `configure(for:)` and
//  `transitionProgress`. Design sections 1 and 8 reinstate the pinch-and-hold
//  and the bloom swap in phase 4, so the switch is dormant here rather than
//  removed -- deleting it would only mean writing it again.
//

import Foundation
import RealityKit
import simd
import Combine
import HearthCore
import HearthUI

#if canImport(UIKit)
import UIKit
#endif

/// How the rig should look, independent of why.
///
/// The turn state machine lives in HearthCore and this layer does not import
/// it: a host maps `HearthState` to one of these. That indirection is what lets
/// the behaviour director in phase 3 drive the same rig from a `behavior_cue`
/// without inventing a second state machine to fight the first.
public enum PersonaState: Sendable {
    case resting
    case listening
    case thinking
    case speaking

    /// The mapping every host uses. Here rather than in each host so two hosts
    /// cannot disagree about what LOADING looks like.
    public init(_ state: HearthState) {
        switch state {
        case .LISTENING: self = .listening
        case .THINKING:  self = .thinking
        case .SPEAKING:  self = .speaking
        case .LOADING, .IDLE: self = .resting
        }
    }
}

@MainActor
public final class PersonaRig: ObservableObject {
    /// What a host adds to its scene. Holds the bead, the glow and the field.
    public private(set) var rootEntity: Entity

    private var sphereEntity: ModelEntity
    private var sphereMaterial: PhysicallyBasedMaterial

    /// The volume's glow: one camera-facing radial sprite. Hidden in immersive,
    /// where a real post-process `BloomComponent` does the job properly.
    private var glowBillboard: ModelEntity?
    private var glowTexture: TextureResource?

    // MARK: - The face

    /// The shell the face is painted on, and the director that decides the pose.
    ///
    /// The shell faces FORWARD and stays there. Neither look-at layer exists
    /// yet, and that is deliberate rather than deferred work: the design's body
    /// layer is a slerp toward the user's head anchor, a head anchor needs a
    /// world-tracking ARKit session, and the Shared Space does not grant one to
    /// a volumetric window. A volume is a box you look into from the front, so
    /// a fixed forward anchor is not an approximation of the intended behaviour
    /// -- it is the whole of it at this scale.
    ///
    /// Phase 4 is where looking-at earns its keep, because that is where the
    /// orb roams a room and the person moves around it. Both layers land there,
    /// against the real anchor the immersive space provides.
    private var faceShell: ModelEntity?
    private var faceTexture: PersonaFaceTexture?
    private var faceDirector: FaceDirector?
    private var faceGeometry = FaceGeometry()
    private var faceClock: Double = 0

    /// The behaviour currently playing, mirrored so SwiftUI can see it.
    ///
    /// BehaviorDirector is a plain class -- deliberately, because it is ticked
    /// from a render loop and an ObservableObject that published sixty times a
    /// second would push the whole stage through SwiftUI's diff. But a host
    /// staging a prop for a particular performance needs to KNOW when one
    /// starts, and `onChange` on a plain property only samples when the body
    /// re-renders for some unrelated reason. So the rig, which is already an
    /// ObservableObject, mirrors the one field a view has to react to, and
    /// publishes only on the edges.
    @Published public private(set) var performingBehavior: String?

    /// True when the compute face is live. False means the host should mount
    /// `PersonaFaceView` as a billboard attachment instead -- degraded, never
    /// faceless.
    public var hasComputeFace: Bool { faceTexture != nil }


    /// Set by the immersive host in phase 4. `BloomComponent` has no effect in
    /// the Shared Space, which is exactly why the billboard exists for the
    /// volume; with real bloom running it is redundant and would double up.
    public var realBloomActive = false {
        // Through `setOrbVisible`, never straight at the billboard.
        //
        // This used to write `glowBillboard?.isEnabled` directly, which meant
        // any host calling `configure(for:)` switched the halo back on -- under
        // a MODEL persona as well, who has no orb for it to be the glow of. So
        // Selene arrived in the room wearing a bead's halo, and the only reason
        // the box did not show it was that nothing called `configure` there
        // after her model loaded.
        //
        // Every path that changes what is visible goes through one function
        // now, and that function knows who is on stage. Same lesson
        // `setConnected` learned first.
        didSet { setOrbVisible(!modelActive) }
    }

    /// Volume or room. The bead and the field are identical in both; only the
    /// glow differs. One place, so the same rig reads the same in both scenes.
    public enum PresentationMode: Sendable { case volumetric, immersive }

    public func configure(for mode: PresentationMode) {
        realBloomActive = (mode == .immersive)
    }

    /// Drives the volume-to-room switch flourish: 0 is the normal per-state
    /// choreography, 1 is the full portal ring. Phase 4's host ramps it while
    /// the pinch-and-hold builds.
    public var transitionProgress: Float = 0

    /// Where the orb goes and why.
    ///
    /// Owned here so the rig ticks it on the same frame it ticks everything
    /// else, but it decides only POSITION -- what the bead looks like while it
    /// travels stays the rig's business, and what its eyes do stays the face's.
    /// Three things that never argue because they never overlap.
    public let behavior = BehaviorDirector()

    /// The rig's resting place, in its parent's space.
    ///
    /// The host sets this to wherever it put the orb; the director's offsets
    /// are applied on top. Kept separate from the entity's own position because
    /// a behaviour has to know what "home" means to return to it, and reading
    /// it back off an entity mid-flight would return wherever the flight had
    /// got to.
    public var homePosition: SIMD3<Float> = .zero {
        didSet { behavior.home = homePosition }
    }

    // MARK: - The model personas

    /// Where a `glb_animated` persona stands. A child of the rig root, so a
    /// model travels, turns and returns home exactly as the bead does -- the
    /// behaviour director never learns which one it is moving.
    private let modelHost = Entity()

    /// Where a host hangs work that should TRAVEL with the persona: cards, the
    /// live caption, anything that belongs to whoever is on stage.
    ///
    /// Design section 6 asked for this from the start -- "cards anchor to the
    /// rig, not the scene" -- and `CardOrbitLayout.offsetFromOrb` has been
    /// sitting unused waiting for it. The volume placed them absolutely
    /// instead, which was the right call while the persona was a bead the size
    /// of a plum: it never moved far and it never got in front of anything.
    /// A standing figure does both, and her head is exactly where the caption
    /// was.
    ///
    /// Scale-cancelled like `modelHost`, so an attachment parented here keeps
    /// the size its own frame gave it rather than inheriting how big the bead
    /// is. Positions on its children are therefore in the HOST's metres.
    ///
    /// It does inherit the rig's yaw, so work turns when the persona turns.
    /// That is the design's intent and is currently untested, because
    /// `BehaviorDirector.motion` is `.none` and the rig never turns.
    public let personaAnchor = Entity()
    private var modelLoader: PersonaModelLoader?
    private var visualization: PersonaVisualization = .fallback
    private var modelLoadToken = 0

    /// True once a model is actually STANDING, not merely asked for.
    ///
    /// Published because the host's tap gesture targets a different entity in
    /// each mode, and a gesture is rebuilt with the body. Nothing else in this
    /// file needs to notify, which is why the flag is the only new @Published.
    @Published public private(set) var modelActive = false

    /// True once the model's one-shot fit has landed and its size is FINAL.
    ///
    /// Published for the same reason `modelActive` is, and it is a second flag
    /// rather than a refinement of the first because they answer different
    /// questions at different moments. `modelActive` says the bead is down and
    /// the figure is up, which is true 800ms before the figure is the right
    /// size; a host measuring against her -- `crownHeight` -- would otherwise
    /// place work against the raw USDZ and then never hear that it changed.
    @Published public private(set) var modelFramed = false

    /// Life size, in metres, and it is the phone's own number: 1.34 is a
    /// standing figure framed full-length. `modelPresentationScale` is a
    /// fraction OF THIS, which is what makes 1.0 mean "as tall as she would
    /// really be".
    private let modelLifeHeight: Float = 1.34
    private let modelLifeWidth: Float = 1.15

    /// How big a model persona is SHOWN, as a fraction of life size.
    ///
    /// The library's trick, applied to a person: author at life size, present
    /// at any size. 1.0 is the default and is what an immersive room wants --
    /// a person standing in your room is a person-sized person. A volumetric
    /// window is 80cm wide and wants a figure on a table instead, so its host
    /// sets a fraction and nothing else in the rig has to know about boxes.
    ///
    /// Independent of the bead's scale on purpose. The host scales
    /// `rootEntity` to say how big SULIVAN'S BEAD is in this box -- a fact
    /// about a bead -- and a person is not sized by it. So the model host
    /// divides that scale back out and this number is measured against the
    /// room, not against the orb.
    public var modelPresentationScale: Float = 1.0 {
        didSet { layoutPersonaHosts() }
    }

    /// How far a model persona is lifted off where the rig sits, in METRES of
    /// the host's own space.
    ///
    /// Zero by default, and that is right for a room: a person standing on your
    /// floor stands on your floor. A volumetric window is the exception -- its
    /// composer and button shelf are ornaments hanging along the bottom edge,
    /// and a figure grounded in the box stands with her legs through both of
    /// them. So the host that put controls there says how far to clear them.
    ///
    /// Stated in the host's metres rather than the rig's units, for the same
    /// reason `modelPresentationScale` is: 8cm should mean 8cm, not 8cm
    /// multiplied by however big the bead happens to be.
    public var modelVerticalOffset: Float = 0 {
        didSet { layoutPersonaHosts() }
    }

    private let particleField = Entity()
    private var particleEntities: [ModelEntity] = []
    private var particleBasePositions: [SIMD3<Float>] = []
    private var particleOrbitAngles: [Float] = []
    private var particleOrbitSpeeds: [Float] = []
    private var particleAnimSpeeds: [Float] = []
    private var particleVerticalSpeeds: [Float] = []
    /// Per-particle twinkle offsets, so the idle field breathes out of step
    /// with itself rather than pulsing as one lamp.
    private var particleTwinklePhases: [Float] = []
    private var particleTwinkleSpeeds: [Float] = []
    /// True while the field is carrying per-particle opacity. Lets the other
    /// states clear it exactly once instead of writing 96 components a frame to
    /// say "still fully visible".
    private var twinkling = false

    #if !os(visionOS)
    // iOS only, and the comment is a warning rather than an explanation: on
    // visionOS the SYSTEM owns the viewer pose, and creating or even touching a
    // PerspectiveCamera inside a volumetric window crashes the device. This is
    // the one API divergence the platform floor cannot paper over.
    private let camera = PerspectiveCamera()
    #endif

    // MARK: - The visualization spec (sulivan.json)

    private let sphereRadius: Float = 0.24
    private let sphereAlpha: Float = 1.0
    private let sphereMetallic: Float = 0.5
    private let sphereRoughness: Float = 0.4
    /// Generous on purpose: a gaze target the size of the bead is a gaze target
    /// people miss.
    private let tapTargetRadius: Float = 0.46
    private let particleCount = 96
    private let particleRadius: Float = 0.010
    private let particleMaxDistance: Float = 0.48
    /// Disconnected: a dull, blacked-out bead. The orb IS the connection
    /// indicator, so there is no second one to keep in sync.
    private let deadColor = SIMD3<Float>(0.05, 0.05, 0.07)

    /// The active persona's colours, data-driven from its config. The
    /// choreography is identical for every persona; only these change.
    private var palette = PersonaPalette.fallback
    private var sphereBaseColor: SIMD3<Float> { palette.sphere }
    private var particleColor: SIMD3<Float> { palette.particle }

    // MARK: - Animation state

    private var animationTime: Float = 0
    private var spinAngle: Float = 0
    private var lastUpdateTime: TimeInterval = 0
    private var currentState: PersonaState = .resting

    /// Eased toward the target each frame. The glow seed is overwritten by
    /// `applyStateVisuals(animated: false)` in init; the literal is the warm
    /// resting accent so nothing cold ever flashes on the first frame.
    private var glow = SIMD3<Float>(0.890, 0.604, 0.357)
    private var intensity: Float = 0.35
    private var motion: Float = 0.15
    private var spinSpeed: Float = 0.05
    private var lastDt: Float = 1.0 / 60.0

    /// Real audio level 0...1 -- mic RMS while listening, TTS amplitude while
    /// speaking. Drives the speaking waveform and widens the listening swirl.
    public var audioLevel: Float = 0
    private var smoothedLevel: Float = 0

    /// Connection-driven, and deliberately decoupled from the turn state: a
    /// house that stops answering mid-thought should go dead, not keep thinking.
    private var isAlive: Bool = true

    /// - Parameter embedCamera: a flat iOS `RealityView` needs the scene to
    ///   carry its own camera. A volumetric window or immersive space must NOT
    ///   have one. Ignored on visionOS, where the camera does not exist at all.
    public init(embedCamera: Bool = false) {
        rootEntity = Entity()
        rootEntity.name = "PersonaRig"

        #if !os(visionOS)
        if embedCamera {
            camera.camera.fieldOfViewInDegrees = 60
            camera.position = SIMD3<Float>(0, 0, 1.25)
            rootEntity.addChild(camera)
        }
        #endif

        sphereMaterial = PhysicallyBasedMaterial()
        let sphereMesh = MeshResource.generateSphere(radius: sphereRadius)
        sphereEntity = ModelEntity(mesh: sphereMesh, materials: [sphereMaterial])
        sphereEntity.name = "PersonaBead"

        configureSphereMaterial()
        rootEntity.addChild(sphereEntity)

        buildGlowBillboard()
        buildFace()

        rootEntity.addChild(particleField)
        buildParticles()

        modelHost.name = "PersonaModelHost"
        rootEntity.addChild(modelHost)
        personaAnchor.name = "PersonaAnchor"
        rootEntity.addChild(personaAnchor)
        layoutPersonaHosts()

        // The rig ticks ITSELF, in whatever scene it is currently in.
        //
        // Weak on purpose: the rig owns `rootEntity`, `rootEntity` holds this
        // component, and the component holds this closure. A strong capture
        // here is a cycle that keeps the rig, its model, its textures and its
        // Metal pipeline alive for the life of the process.
        rootEntity.components.set(ClosureComponent { [weak self] deltaTime in
            self?.update(deltaTime: deltaTime)
        })

        applyStateVisuals(animated: false)
    }

    /// The face shell: a sphere a hair larger than the bead, wearing the
    /// compute texture, blended on that texture's own alpha.
    ///
    /// Unlit rather than physically based, and that is the "emissive-weighted"
    /// binding the design asks for: the ink is not lit by the room, it glows
    /// with the body and clears the bloom threshold along with it. The same
    /// material shape the glow billboard already uses, which is the one
    /// alpha-textured material in this file proven to composite correctly.
    private func buildFace() {
        guard let texture = PersonaFaceTexture() else {
            // Said out loud, because the visible symptom of this -- a flat face
            // billboarded in front of the bead instead of painted on it -- is
            // subtle enough to be mistaken for a texture bug.
            log.error("compute face unavailable; the host should mount the SwiftUI fallback")
            return
        }
        faceTexture = texture
        faceDirector = FaceDirector(geometry: faceGeometry, now: 0)

        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture.textureResource))
        material.blending = .transparent(opacity: 1.0)

        // 1.02: clear of the bead's own surface so the two do not z-fight, and
        // close enough that the ink reads as painted ON the orb rather than
        // floating in front of it.
        let shell = ModelEntity(mesh: .generateSphere(radius: sphereRadius * 1.02),
                                materials: [material])
        shell.name = "PersonaFace"

        // A quarter turn, and it is measured rather than reasoned.
        //
        // The kernel paints the face where its own longitude is zero, but which
        // world direction that lands on depends on where RealityKit's sphere
        // generator puts its UV seam -- a property of a mesh we did not author
        // and Apple does not document. On the device the face came up looking
        // along -X, a quarter turn to the viewer's left, so the shell turns a
        // quarter the other way and the face looks out of the volume.
        //
        // Turning the SHELL rather than the kernel's `longitudeOffset` on
        // purpose: this is a fact about the mesh, and it is worth stating in
        // the units the observation was made in. `longitudeOffset` stays free
        // for tuning the face's own placement.
        shell.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0))

        // No BillboardComponent, and the absence is the decision: the face is
        // painted at the front of this shell and the shell does not turn, so
        // the face looks forward out of the volume. See the note on `faceShell`.
        sphereEntity.addChild(shell)
        faceShell = shell
    }

    // MARK: - Build

    private func configureSphereMaterial() {
        sphereMaterial.baseColor = .init(tint: rigColor(sphereBaseColor, alpha: sphereAlpha))
        sphereMaterial.metallic = .init(floatLiteral: sphereMetallic)
        sphereMaterial.roughness = .init(floatLiteral: sphereRoughness)
        // A glassy clear coat over the metal: polished highlight, reflecting
        // passthrough like a bead actually sitting in the room.
        sphereMaterial.clearcoat = .init(floatLiteral: 0.25)
        sphereMaterial.clearcoatRoughness = .init(floatLiteral: 0.4)
        sphereMaterial.blending = .opaque
        sphereMaterial.emissiveColor = .init(color: rigColor(palette.idle))
        sphereMaterial.emissiveIntensity = 1.4
        sphereEntity.model?.materials = [sphereMaterial]
    }

    /// Factored out so a palette swap can re-tint all 96 particles at once.
    private func particleMaterial() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: rigColor(particleColor))
        material.metallic = .init(floatLiteral: sphereMetallic)
        material.roughness = .init(floatLiteral: sphereRoughness)
        material.clearcoat = .init(floatLiteral: 1.0)
        material.clearcoatRoughness = .init(floatLiteral: 0.1)
        material.emissiveColor = .init(color: rigColor(particleColor))
        // The metallic body darkens the dot, so the emissive has to clear the
        // bloom threshold (the orb blooms around 1.7 to 2.9). 1.15 was under it
        // and the field simply did not glow.
        material.emissiveIntensity = 2.5
        return material
    }

    // MARK: - Persona palette

    /// Swap in a persona's colours. Cheap to call every frame: it early-returns
    /// when nothing changed, which is what lets a host apply it from the update
    /// loop without caring whether the config has arrived yet.
    public func apply(_ newPalette: PersonaPalette) {
        guard newPalette != palette else { return }
        palette = newPalette

        // Particles carry their tint in their own materials, so always re-tint.
        // While disconnected they are hidden rather than recoloured, and pick
        // this up on revive.
        let mat = particleMaterial()
        for entity in particleEntities { entity.model?.materials = [mat] }

        // The bead's materials belong to the dead look while disconnected.
        if isAlive {
            configureSphereMaterial()
            applyStateVisuals(animated: true)
        }
    }

    private func buildParticles() {
        // Deterministic Fibonacci shell: the same field every launch, and the
        // same field every client.
        let golden = Float.pi * (3.0 - sqrt(5.0))
        let mesh = MeshResource.generateSphere(radius: particleRadius)

        for i in 0..<particleCount {
            let y = 1.0 - (Float(i) / Float(particleCount - 1)) * 2.0
            let r = sqrt(max(0, 1.0 - y * y))
            let theta = golden * Float(i)
            let innerEdge = sphereRadius + 0.04
            let dist = innerEdge + pseudoRandom(i) * (particleMaxDistance - innerEdge)
            let pos = SIMD3<Float>(cos(theta) * r * dist, y * dist, sin(theta) * r * dist)
            particleBasePositions.append(pos)

            particleOrbitAngles.append(theta)
            particleOrbitSpeeds.append(0.10 + pseudoRandom(i + 101) * 0.30)
            particleAnimSpeeds.append(0.10 + pseudoRandom(i + 211) * 0.50)
            particleVerticalSpeeds.append((pseudoRandom(i + 307) - 0.5) * 0.40)
            particleTwinklePhases.append(pseudoRandom(i + 401) * .pi * 2)
            particleTwinkleSpeeds.append(0.55 + pseudoRandom(i + 509) * 0.75)

            let particle = ModelEntity(mesh: mesh, materials: [particleMaterial()])
            particle.position = pos
            particleField.addChild(particle)
            particleEntities.append(particle)
        }
    }

    /// One camera-facing quad with a soft radial-gradient alpha, so it reads as
    /// a round bloom from any angle. Replaced Valinor's layered emissive
    /// spheres, which showed as hard concentric rings.
    private func buildGlowBillboard() {
        glowTexture = Self.makeRadialGlowTexture()
        let size = sphereRadius * 3.6
        let mesh = MeshResource.generatePlane(width: size, height: size)
        let entity = ModelEntity(mesh: mesh,
                                 materials: [glowBillboardMaterial(color: palette.idle, opacity: 0.5)])
        entity.components.set(BillboardComponent())
        rootEntity.addChild(entity)
        glowBillboard = entity
    }

    private func glowBillboardMaterial(color: SIMD3<Float>, opacity: Float) -> UnlitMaterial {
        var mat = UnlitMaterial()
        if let tex = glowTexture {
            mat.color = .init(tint: rigColor(color, alpha: opacity), texture: .init(tex))
        } else {
            mat.color = .init(tint: rigColor(color, alpha: opacity))
        }
        mat.blending = .transparent(opacity: 1.0)
        return mat
    }

    /// One-time radial gradient, opaque white centre to transparent edge, used
    /// as the glow sprite's alpha mask.
    private static func makeRadialGlowTexture(size: Int = 256) -> TextureResource? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let c = CGFloat(size) / 2
        let colors = [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray
        guard let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1]) else { return nil }
        ctx.drawRadialGradient(grad, startCenter: CGPoint(x: c, y: c), startRadius: 0,
                               endCenter: CGPoint(x: c, y: c), endRadius: c, options: [])
        guard let cg = ctx.makeImage() else { return nil }
        return try? TextureResource(image: cg, options: .init(semantic: .color))
    }

    // MARK: - The visualization

    /// Which renderer this persona asked for.
    ///
    /// The dispatch lives HERE rather than in each host, and that is the whole
    /// point: the phone chooses between three views in `HearthMainView`, but a
    /// spatial host would have to choose between three ENTITY TREES and then
    /// re-teach each one about travel, tap targets, palette and state. The rig
    /// already owns all four. So a host hands over the config and the rig
    /// decides, which is what keeps the volume and phase 4's immersive room
    /// from each growing their own copy of this.
    ///
    /// Chosen by `type`, never by name -- the same contract `PersonaVisualization`
    /// states. Nothing here says "if Selene".
    ///
    /// Cheap to call every frame: it early-returns when nothing changed, which
    /// is what lets a host put it beside the palette and geometry calls in one
    /// per-frame block rather than wiring an observer.
    public func apply(visualization newValue: PersonaVisualization) {
        guard newValue != visualization else { return }
        visualization = newValue

        guard newValue.canRenderModel else {
            // Includes the honest fallbacks `PersonaVisualization` already
            // defines: a glb persona whose clips have not reached the server
            // shows the bead rather than an empty stage.
            teardownModel()
            return
        }
        loadModel(newValue)
    }

    private func loadModel(_ newValue: PersonaVisualization) {
        modelLoadToken += 1
        let token = modelLoadToken

        // Recomputed here rather than trusted from init: the host sets the rig
        // root's scale after constructing the rig, and these numbers are
        // measured against it. Doing it at the moment a model actually arrives
        // makes the host's ordering irrelevant.
        layoutPersonaHosts()

        // The old one goes NOW, not when the new one arrives: switching away
        // from Selene should not leave her standing while Sage downloads.
        modelLoader?.unload()
        modelFramed = false
        let loader = PersonaModelLoader()
        modelLoader = loader
        // The collision box is measured AFTER the fit, not when `load` returns.
        // Framing is a delayed one-shot inside the loader, so a box measured on
        // return is a box around the un-fitted model -- a pinch target several
        // times the size of the figure standing in it.
        loader.onFramed = { [weak self] in
            guard let self, token == self.modelLoadToken else { return }
            self.applyModelCollision()
            self.modelFramed = true
        }

        Task { @MainActor [weak self] in
            await loader.load(visualization: newValue,
                              into: self?.modelHost ?? Entity(),
                              fitHeight: self?.modelLifeHeight ?? 1.34,
                              fitWidth: self?.modelLifeWidth ?? 1.15)
            guard let self, token == self.modelLoadToken else {
                // A third persona was chosen while this one was downloading.
                loader.unload()
                return
            }
            guard loader.isLoaded else {
                // A model that would not load is not a reason to show nothing.
                log.error("model persona failed to load; keeping the bead")
                self.teardownModel()
                return
            }
            self.modelActive = true
            self.setOrbVisible(false)
            // NO collision yet, deliberately. The first cut set a provisional
            // box here from the un-fitted model, which for a USDZ authored at
            // a hundred times its final size is a box around the whole room --
            // and for the second before the fit lands, every pinch in the
            // scene landed on it instead of on what was aimed at. She is not
            // pinchable until `onFramed` says how big she actually is.
            loader.play(state: self.hearthState)
        }
    }

    private func teardownModel() {
        modelLoadToken += 1
        modelLoader?.unload()
        modelLoader = nil
        modelFramed = false
        guard modelActive else { return }
        modelActive = false
        setOrbVisible(true)
    }

    /// The bead and everything that belongs to it. Toggled rather than removed
    /// so a switch back is instant and keeps its animation state.
    /// The bead and everything that belongs to it: its shell, its face, its
    /// particle field, its halo.
    ///
    /// The one place that decides what a persona is made of, and it decides on
    /// `modelActive` -- which is to say on the visualization TYPE. A bead is a
    /// light and carries light's furniture; a body carries none of it, and a
    /// body wearing a bead's halo is two personas on one stage. Phase 4.5's
    /// rule that non-corporeal personas get effects and humanoid ones do not
    /// starts here rather than at each effect.
    private func setOrbVisible(_ visible: Bool) {
        sphereEntity.isEnabled = visible
        particleField.isEnabled = visible && isAlive
        glowBillboard?.isEnabled = visible && isAlive && !realBloomActive
        faceShell?.isEnabled = visible && isAlive
    }

    /// The model host's own scale: the presentation fraction, with the rig
    /// root's scale divided back out so the fraction is measured against the
    /// room rather than against the bead.
    /// Whether whoever is on stage has a BODY.
    ///
    /// The distinction earns its keep in more than one place, which is why it
    /// is named rather than open-coded as `modelActive` at each site. A body
    /// STANDS -- on the floor of a room, on the floor of a box -- where a bead
    /// floats at a conversational height. And a bead is a LIGHT: it blooms, it
    /// throws colour on the walls, it carries a particle field. A person
    /// standing in your room who casts caustics on your ceiling is a different
    /// and stranger proposition, so effects follow this too.
    ///
    /// Derived from the visualization kind rather than from the persona's name,
    /// like everything else here.
    public var isCorporeal: Bool { modelActive }

    /// Where the rig is right now, in the IMMERSIVE SPACE's coordinates.
    ///
    /// RealityKit has two named coordinate spaces: `.scene`, whose origin is
    /// the centre-back of the volumetric window, and `.immersiveSpace`, whose
    /// origin is the point on the ground below you. This converts between them,
    /// which is what lets the persona leave the box at the place she was
    /// actually standing rather than at a guess.
    ///
    /// Only meaningful WHILE an immersive space is open, so a host has exactly
    /// one moment to call it: after the space has opened and before the volume
    /// goes. NIL is the platform telling you that you called it outside that
    /// moment -- which is worth passing along rather than papering over, since
    /// the honest fallback is a sensible spot in front of the person and a
    /// silently-identity matrix would put her inside the floor.
    ///
    /// It lives here rather than at the call site for a dull reason with a real
    /// cost: this returns a `simd_float4x4` and needs `import RealityKit`, and
    /// importing RealityKit into a file that declares an `App` makes `Scene`
    /// ambiguous between RealityKit's and SwiftUI's. The rig knowing how to
    /// measure itself is also the better shape.
    /// Guarded because `.immersiveSpace` does not exist on iOS -- there are no
    /// immersive spaces there -- and this target builds for iOS as a gate. The
    /// nil an iOS caller gets is the same nil a mistimed visionOS caller gets,
    /// and means the same thing: no room to measure against.
    public func transformInImmersiveSpace() -> simd_float4x4? {
        #if os(visionOS)
        return rootEntity.transformMatrix(relativeTo: .immersiveSpace)
        #else
        return nil
        #endif
    }

    /// Set how big the BEAD is in this host, and re-derive everything measured
    /// against it.
    ///
    /// Hosts used to write `rootEntity.scale` directly, which was fine while
    /// there was one host. There are two now, they want different numbers, and
    /// `modelPresentationScale` and `personaAnchor` are both expressed as
    /// fractions OF this -- so a host changing it behind their back leaves a
    /// model at the wrong size and work hanging at the wrong offsets.
    public func setRigScale(_ scale: Float) {
        rootEntity.scale = SIMD3<Float>(repeating: scale)
        layoutPersonaHosts()
    }

    /// How high the top of whoever is on stage sits above the rig's own
    /// origin, in the host's METRES.
    ///
    /// This is what makes "above their head" mean the same thing for a bead the
    /// size of a plum and a figure half a metre tall, without a host having to
    /// know which one it is looking at. A model that has loaded is measured;
    /// anything else falls back to the nominal size, which is exact for the
    /// bead and a good guess for a model mid-download.
    public var crownHeight: Float {
        let rigScale = max(rootEntity.scale.x, 0.0001)
        guard modelActive else { return sphereRadius * rigScale }
        // Only measured once the fit has landed. Before then the model is still
        // the size the artist exported, and measuring it would throw the
        // caption metres into the room for the second it takes to settle.
        guard modelFramed else {
            return modelVerticalOffset + modelLifeHeight * modelPresentationScale * 0.5
        }
        let bounds = modelHost.visualBounds(relativeTo: rootEntity)
        guard bounds.extents.y > 0.0001 else {
            return modelVerticalOffset + modelLifeHeight * modelPresentationScale * 0.5
        }
        return bounds.max.y * rigScale
    }

    private func layoutPersonaHosts() {
        let rigScale = max(rootEntity.scale.x, 0.0001)
        modelHost.scale = SIMD3<Float>(repeating: modelPresentationScale / rigScale)
        // The same division, for the same reason: a child's position is in its
        // PARENT's units, and the parent here is the rig root the host scaled.
        modelHost.position = SIMD3<Float>(0, modelVerticalOffset / rigScale, 0)
        // The anchor sits at the rig's own origin, cancelling only the scale.
        // Sitting AT the origin rather than at the crown is deliberate: cards
        // are laid out around the persona's centre by `offsetFromOrb`, and the
        // caption asks for `crownHeight` explicitly. One anchor, two rules,
        // rather than an anchor that has already assumed one of them.
        personaAnchor.scale = SIMD3<Float>(repeating: 1 / rigScale)
    }

    /// A figure has to be pinchable too, and a USDZ arrives with no collision
    /// shape of its own. Sized from what actually loaded rather than from a
    /// constant: the bead's `tapTargetRadius` is a sphere around a sphere, and
    /// a standing person is neither.
    ///
    /// Only ever called once the fit has landed -- see `onFramed`. A box
    /// measured before then is a box around the raw USDZ, which is the size the
    /// artist exported and has nothing to do with the size on screen.
    private func applyModelCollision() {
        #if os(visionOS)
        let bounds = modelHost.visualBounds(relativeTo: modelHost)
        guard bounds.extents.y > 0.0001,
              // A last guard against measuring at the wrong moment: a person is
              // never twice her own life height, so anything that says she is
              // has measured something other than her.
              bounds.extents.y < modelLifeHeight * 2 else { return }
        let shape = ShapeResource.generateBox(size: bounds.extents)
            .offsetBy(translation: bounds.center)
        modelHost.components.set(CollisionComponent(shapes: [shape]))
        modelHost.components.set(InputTargetComponent())
        modelHost.components.set(HoverEffectComponent())
        #endif
    }

    // MARK: - State

    public func updateState(_ newState: PersonaState) {
        guard newState != currentState else { return }
        currentState = newState
        applyStateVisuals(animated: true)
        // A model persona says the state with a CLIP rather than with colour.
        // Same four names the orb's choreography uses, so a persona that ships
        // three of them falls back to idle for the fourth exactly as the phone
        // does.
        modelLoader?.play(state: hearthState)
    }

    /// Alive or dead, from the connection status. Independent of the turn
    /// state: reconnecting revives into whatever state the rig currently holds.
    public func setConnected(_ connected: Bool) {
        guard connected != isAlive else { return }
        isAlive = connected
        if connected {
            configureSphereMaterial()
            // Through setOrbVisible rather than directly, so reviving under a
            // model persona does not raise the bead through the middle of her.
            setOrbVisible(!modelActive)
            applyStateVisuals(animated: false)
        } else {
            applyDeadLook()
        }
    }

    /// `update(deltaTime:)` early-returns while dead, so this is not overwritten
    /// on the next frame.
    private func applyDeadLook() {
        particleField.isEnabled = false
        glowBillboard?.isEnabled = false
        // The face goes with the light. A dead bead that still blinks at you is
        // worse than a dead bead: it says the house is there when it is not.
        faceShell?.isEnabled = false
        sphereEntity.scale = .one
        sphereMaterial.baseColor = .init(tint: rigColor(deadColor, alpha: 1.0))
        sphereMaterial.metallic = .init(floatLiteral: 0.0)
        sphereMaterial.roughness = .init(floatLiteral: 0.95)
        sphereMaterial.clearcoat = .init(floatLiteral: 0.0)
        sphereMaterial.emissiveColor = .init(color: rigColor(.zero))
        sphereMaterial.emissiveIntensity = 0
        sphereMaterial.blending = .opaque
        sphereEntity.model?.materials = [sphereMaterial]
    }

    /// Target params per state. The glow colour is the persona's accent, data
    /// driven; the intensity, motion and spin tuning is shared choreography.
    private func applyStateVisuals(animated: Bool) {
        let target: (glow: SIMD3<Float>, intensity: Float, motion: Float, spin: Float)
        switch currentState {
        case .resting:   target = (palette.idle, 1.3, 0.15, 0.06)
        case .listening: target = (palette.listening, 2.2, 0.8, 0.28)
        case .thinking:  target = (palette.thinking, 1.6, 0.5, 0.40)
        case .speaking:  target = (palette.speaking, 2.0, 0.7, 0.30)
        }
        if animated {
            visualTarget = target
        } else {
            glow = target.glow; intensity = target.intensity
            motion = target.motion; spinSpeed = target.spin
            visualTarget = target
        }
    }

    private var visualTarget: (glow: SIMD3<Float>, intensity: Float, motion: Float, spin: Float)
        = (SIMD3<Float>(0.890, 0.604, 0.357), 0.35, 0.15, 0.05)

    // MARK: - Per-frame update

    public func update(deltaTime: TimeInterval) {
        guard isAlive else { return }

        // The host's tick is the clock. `deltaTime` from SceneEvents.Update is
        // the frame delta already; the wall-clock read Valinor did here made
        // the rig depend on Date() sixty times a second for no gain.
        let dt = deltaTime > 0 ? Float(deltaTime) : 1.0 / 60.0
        lastDt = dt
        animationTime += dt

        smoothedLevel = smoothedLevel * 0.6 + max(0, min(1, audioLevel)) * 0.4

        let k: Float = min(1, dt * 4)
        glow = mix(glow, visualTarget.glow, k)
        intensity = lerp(intensity, visualTarget.intensity, k)
        motion = lerp(motion, visualTarget.motion, k)
        spinSpeed = lerp(spinSpeed, visualTarget.spin, k)

        // The bead's own look, and only the bead's. A model persona says every
        // one of these things with a clip instead -- breath, glow, the swell on
        // a spoken syllable -- so driving them under her would be spending a
        // frame's work on hidden geometry.
        if !modelActive {
            // Breathing, plus the speaking "wavelength" which is the REAL TTS
            // amplitude rather than a synthetic wobble.
            let breathe = 1.0 + 0.04 * sin(animationTime * 1.2)
            let pulse: Float = (currentState == .speaking) ? smoothedLevel : 0
            let swell = breathe + 0.18 * pulse

            sphereEntity.scale = SIMD3<Float>(repeating: swell)
            sphereMaterial.emissiveColor = .init(color: rigColor(glow))
            sphereMaterial.emissiveIntensity = intensity * 1.3 + 0.3 * pulse
            sphereMaterial.baseColor = .init(tint: rigColor(sphereBaseColor, alpha: sphereAlpha))
            sphereEntity.model?.materials = [sphereMaterial]

            let bloom = min(1.0, intensity * 0.5)
            if let billboard = glowBillboard {
                billboard.model?.materials = [glowBillboardMaterial(color: glow,
                                                                    opacity: 0.4 + 0.4 * bloom + 0.3 * pulse)]
                billboard.scale = SIMD3<Float>(repeating: swell * (1.0 + 0.12 * pulse))
            }

            tickFace(dt: dt)
        }

        // Where the orb is. Speech recalls a behaviour that does not hold its
        // ground, which is why the director is told the state rather than
        // inferring it: only the rig knows whether the house is talking.
        let offset = behavior.tick(dt: dt, speaking: currentState == .speaking)
        rootEntity.position = homePosition + offset
        // The rig turns, which is what makes the face look at anything: the
        // face is painted on the front of a shell that does not billboard, so
        // it looks wherever the rig is pointed.
        rootEntity.orientation = simd_quatf(angle: behavior.yaw, axis: SIMD3<Float>(0, 1, 0))
        // Edges only: this is inside a per-frame tick, and assigning an equal
        // value to a @Published still notifies.
        if behavior.performing != performingBehavior {
            performingBehavior = behavior.performing
        }

        // Everything below is the particle field, which a model persona does
        // not have. The travel above it is deliberately NOT guarded: a figure
        // walks to the shelf exactly as a bead flies to it.
        guard !modelActive else { return }

        // The switch flourish overrides the per-state choreography while the
        // hold builds. Dormant until phase 4 ramps `transitionProgress`.
        if transitionProgress > 0.01 {
            updateSwitchParticles(progress: min(1, transitionProgress))
            return
        }

        switch currentState {
        case .listening: updateListeningParticles()
        case .thinking:  updateThinkingParticles()
        case .speaking:  updateSpeakingParticles(level: smoothedLevel)
        case .resting:   updateShellParticles(pulse: 0)
        }
    }

    // MARK: - The face, per frame

    /// Tick the director and redraw the texture.
    ///
    /// `FaceFeed` is the same singleton the phone's face reads, which is what
    /// makes `tts_chunk_start` land as an expression here without a second wire:
    /// the view model posts a cue and a speech level to the feed, and both
    /// renderers pick them up. The headset does not subscribe to anything the
    /// phone does not.
    ///
    /// The clock is accumulated from the frame delta rather than read from
    /// `Date()`. The director takes milliseconds and clamps its own dt, so any
    /// monotonic source works -- and this one cannot jump backwards when the
    /// system clock is adjusted, which is a failure mode the director's own
    /// comments describe having been bitten by.
    private func tickFace(dt: Float) {
        guard let faceTexture, let faceDirector else { return }
        faceClock += Double(dt) * 1000

        let feed = FaceFeed.shared
        let pose = faceDirector.tick(
            now: faceClock,
            state: faceState,
            cue: feed.cue,
            speechLevel: feed.speechLevel,
            reduceMotion: false,
            // No look target in a volume. The playlist and its saccades own the
            // gaze, which is what the director does when nothing is named --
            // the eyes still move, they just are not tracking anything.
            lookTarget: nil)

        faceTexture.draw(pose: pose, palette: palette, state: hearthState)
    }

    /// The face's reading of the turn.
    ///
    /// The rig speaks in `PersonaState` and the director in `FaceState`; they
    /// are the same four beats under different names, and this is the one place
    /// that has to know both.
    private var faceState: FaceState {
        switch currentState {
        case .listening: return .listening
        case .thinking:  return .thinking
        case .speaking:  return .speaking
        case .resting:   return .idle
        }
    }

    /// The turn state the face's COLOUR wash reads.
    ///
    /// `PersonaPalette.glow(for:)` is keyed on HearthState, so the rig has to
    /// hand one back. Kept alongside `currentState` rather than stored, because
    /// two fields that must agree are two fields that will not.
    private var hearthState: HearthState {
        switch currentState {
        case .listening: return .LISTENING
        case .thinking:  return .THINKING
        case .speaking:  return .SPEAKING
        case .resting:   return .IDLE
        }
    }

    /// Swap in a persona's face geometry, rebuilding the director around it.
    ///
    /// The director caches its playlist against the geometry it was built for,
    /// exactly as the phone's DirectorBox does, so a geometry that arrives late
    /// from `persona_config` reshapes the face rather than being ignored.
    public func apply(faceGeometry newGeometry: FaceGeometry) {
        guard newGeometry != faceGeometry else { return }
        faceGeometry = newGeometry
        faceDirector = FaceDirector(geometry: newGeometry, now: faceClock)
    }

    // MARK: - Per-state choreography

    /// Resting: particles ride their base shell, the field spins and expands,
    /// and each dot fades in and out on its own clock.
    ///
    /// The twinkle is what turns a swarm into fireflies. At rest the field's job
    /// is to say the house is alive, and 96 dots all present at once say it by
    /// crowding the face -- the one thing on the orb worth looking at. Fading
    /// each in and out means the field is never fully in front of the face and
    /// never fully absent either.
    private func updateShellParticles(pulse: Float) {
        spinAngle += spinSpeed * lastDt * Float.pi * 2
        particleField.orientation = simd_quatf(angle: spinAngle, axis: SIMD3<Float>(0, 1, 0))
        particleField.scale = SIMD3<Float>(repeating: 1.0 + 0.5 * motion + 0.3 * pulse)
        for i in particleEntities.indices {
            particleEntities[i].position = particleBasePositions[i]
            // A raised sine, floored at ZERO. Each dot is genuinely absent for
            // half its cycle rather than merely dim.
            //
            // The floor was 0.12 and that was the whole failure: a hundred dots
            // at a tenth opacity are still a hundred dots, so the field read as
            // cluttered haze instead of fireflies. Vanishing outright is what
            // declutters WITHOUT losing particles -- the same field, a third of
            // it visible at any moment.
            //
            // OpacityComponent rather than per-particle materials: 96 material
            // assignments a frame to change one number would be absurd, and
            // this is the component that exists for exactly this.
            let wave = sin(animationTime * particleTwinkleSpeeds[i] + particleTwinklePhases[i])
            particleEntities[i].components.set(OpacityComponent(opacity: max(0, wave)))
        }
        twinkling = true
    }

    /// Put every particle back to full opacity, once.
    ///
    /// Called by the states that do not twinkle. Guarded because it only needs
    /// to happen on the way out of idle, and writing 96 components a frame to
    /// say "still fully visible" is work for nothing.
    private func clearTwinkle() {
        guard twinkling else { return }
        twinkling = false
        for entity in particleEntities {
            entity.components.set(OpacityComponent(opacity: 1))
        }
    }

    /// Listening: a firefly swirl in the VERTICAL plane, widening with the mic.
    ///
    /// Turned a quarter from Valinor's, and the reason is the face. The
    /// original swirls around the Y axis, which on a bead with no face is a
    /// pleasing halo and on a bead WITH one is a curtain drawn across it. Swung
    /// into the plane the viewer faces, the same motion frames the face instead
    /// of crossing it. The z jitter is what keeps it from reading as a flat
    /// sticker: the dots still have depth, they just no longer orbit through
    /// the eyes.
    private func updateListeningParticles() {
        particleField.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        particleField.scale = .one
        clearTwinkle()
        let maxD = particleMaxDistance
        for i in particleEntities.indices {
            particleOrbitAngles[i] += particleOrbitSpeeds[i] * lastDt * 4
            let angle = particleOrbitAngles[i]
            let pulsing = 0.5 + 0.5 * sin(animationTime * particleAnimSpeeds[i])
            let dist = maxD * min(1, 0.6 + 0.4 * pulsing)
            let breathe = sin(animationTime * 0.5 + angle) * 0.05 * maxD
            let jitterZ = sin(animationTime * particleVerticalSpeeds[i]) * 0.18 * maxD
            particleEntities[i].position = SIMD3<Float>(
                cos(angle) * (dist + breathe),
                sin(angle) * (dist + breathe),
                jitterZ)
        }
    }

    /// Thinking: the ring stood upright, roughly twice as fast.
    ///
    /// Valinor's is a flat Saturn ring at the bead's height, which from the
    /// front is a line straight through the eyes. Stood up into the viewer's
    /// plane it becomes a halo around the face -- the same shape, doing the
    /// opposite thing to the one feature that matters.
    private func updateThinkingParticles() {
        particleField.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        particleField.scale = .one
        clearTwinkle()
        let ringD = particleMaxDistance * 0.86
        for i in particleEntities.indices {
            particleOrbitAngles[i] += particleOrbitSpeeds[i] * lastDt * 8
            let angle = particleOrbitAngles[i]
            particleEntities[i].position = SIMD3<Float>(cos(angle) * ringD, sin(angle) * ringD, 0)
        }
    }

    /// The switch flourish: a TILTED portal ring, deliberately distinct from
    /// the flat thinking ring so the two never read as the same event.
    private func updateSwitchParticles(progress: Float) {
        particleField.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        particleField.scale = .one
        clearTwinkle()
        let n = particleEntities.count
        let ringD = particleMaxDistance * (1.0 - 0.3 * progress)
        let tilt: Float = 0.6
        let spin = animationTime * (3.0 + 6.0 * progress)
        for i in particleEntities.indices {
            let t = n <= 1 ? 0 : Float(i) / Float(n)
            let angle = t * Float.pi * 2 + spin
            let x = cos(angle) * ringD
            let yFlat = sin(angle) * ringD
            let y = yFlat * cos(tilt)
            let z = yFlat * sin(tilt)
            particleEntities[i].position = mix(particleBasePositions[i], SIMD3<Float>(x, y, z), progress)
        }
    }

    /// Speaking: a horizontal waveform line whose height is the real playback
    /// amplitude, in front of the bead and facing the viewer.
    private func updateSpeakingParticles(level: Float) {
        particleField.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        particleField.scale = .one
        clearTwinkle()
        let n = particleEntities.count
        let width = particleMaxDistance * 1.8
        let halfW = width / 2
        // A small floor keeps the line alive between syllables.
        let amp = (0.04 + 0.5 * level) * particleMaxDistance
        let z = sphereRadius + 0.06
        for i in particleEntities.indices {
            let t = n <= 1 ? 0 : Float(i) / Float(n - 1)
            let x = -halfW + t * width
            // Two components, so it wiggles like a voice rather than a sine.
            let phase = x * 14.0 + animationTime * 7.0
            let y = amp * (sin(phase) * 0.7 + sin(phase * 0.5 + animationTime * 3.0) * 0.3)
            particleEntities[i].position = SIMD3<Float>(x, y, z)
        }
    }

    // MARK: - Interaction

    /// What gaze and pinch gestures target: whichever persona is on stage.
    ///
    /// `modelActive` is @Published for this one line -- a host's gesture is
    /// built with its body, so the body has to be told when the answer changes.
    public var tapTarget: Entity { modelActive ? modelHost : sphereEntity }

    /// Make the bead gaze-targetable and pinchable.
    ///
    /// visionOS only: the input and hover components do not exist on iOS, where
    /// a flat host drives the orb with an ordinary tap gesture instead.
    public func enableInteraction() {
        #if os(visionOS)
        let shape = ShapeResource.generateSphere(radius: tapTargetRadius)
        sphereEntity.components.set(CollisionComponent(shapes: [shape]))
        sphereEntity.components.set(InputTargetComponent())
        sphereEntity.components.set(HoverEffectComponent())
        #endif
    }

    // MARK: - Helpers

    /// SIMD3 to the platform colour RealityKit materials want.
    private func rigColor(_ c: SIMD3<Float>, alpha: Float = 1) -> UIColor {
        UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: CGFloat(alpha))
    }

    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }

    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }

    /// Deterministic per-index pseudo-random in [0,1). Seeded, no allocation,
    /// and identical on every client -- which is what makes the field the same
    /// field everywhere rather than merely a similar one.
    private func pseudoRandom(_ i: Int) -> Float {
        let x = sin(Float(i) * 12.9898) * 43758.5453
        return x - floor(x)
    }
}
