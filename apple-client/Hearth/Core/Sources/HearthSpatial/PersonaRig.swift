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

    /// True when the compute face is live. False means the host should mount
    /// `PersonaFaceView` as a billboard attachment instead -- degraded, never
    /// faceless.
    public var hasComputeFace: Bool { faceTexture != nil }


    /// Set by the immersive host in phase 4. `BloomComponent` has no effect in
    /// the Shared Space, which is exactly why the billboard exists for the
    /// volume; with real bloom running it is redundant and would double up.
    public var realBloomActive = false {
        didSet { glowBillboard?.isEnabled = isAlive && !realBloomActive }
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

    private let particleField = Entity()
    private var particleEntities: [ModelEntity] = []
    private var particleBasePositions: [SIMD3<Float>] = []
    private var particleOrbitAngles: [Float] = []
    private var particleOrbitSpeeds: [Float] = []
    private var particleAnimSpeeds: [Float] = []
    private var particleVerticalSpeeds: [Float] = []

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

    // MARK: - State

    public func updateState(_ newState: PersonaState) {
        guard newState != currentState else { return }
        currentState = newState
        applyStateVisuals(animated: true)
    }

    /// Alive or dead, from the connection status. Independent of the turn
    /// state: reconnecting revives into whatever state the rig currently holds.
    public func setConnected(_ connected: Bool) {
        guard connected != isAlive else { return }
        isAlive = connected
        if connected {
            configureSphereMaterial()
            particleField.isEnabled = true
            glowBillboard?.isEnabled = !realBloomActive
            faceShell?.isEnabled = true
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

    /// Resting: particles ride their base shell; the field spins and expands.
    private func updateShellParticles(pulse: Float) {
        spinAngle += spinSpeed * lastDt * Float.pi * 2
        particleField.orientation = simd_quatf(angle: spinAngle, axis: SIMD3<Float>(0, 1, 0))
        particleField.scale = SIMD3<Float>(repeating: 1.0 + 0.5 * motion + 0.3 * pulse)
        for i in particleEntities.indices {
            particleEntities[i].position = particleBasePositions[i]
        }
    }

    /// Listening: a 3D firefly swirl that widens with the mic level.
    private func updateListeningParticles() {
        particleField.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        particleField.scale = .one
        let maxD = particleMaxDistance
        for i in particleEntities.indices {
            particleOrbitAngles[i] += particleOrbitSpeeds[i] * lastDt * 4
            let angle = particleOrbitAngles[i]
            let pulsing = 0.5 + 0.5 * sin(animationTime * particleAnimSpeeds[i])
            let dist = maxD * min(1, 0.6 + 0.4 * pulsing)
            let bobY = sin(animationTime * particleVerticalSpeeds[i]) * 0.15 * maxD
            let swirlY = sin(animationTime * 0.5 + angle) * 0.05 * maxD
            particleEntities[i].position = SIMD3<Float>(cos(angle) * dist, bobY + swirlY, sin(angle) * dist)
        }
    }

    /// Thinking: a flat Saturn ring at the bead's height, roughly twice as fast.
    private func updateThinkingParticles() {
        particleField.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        particleField.scale = .one
        let ringD = particleMaxDistance * 0.8
        for i in particleEntities.indices {
            particleOrbitAngles[i] += particleOrbitSpeeds[i] * lastDt * 8
            let angle = particleOrbitAngles[i]
            particleEntities[i].position = SIMD3<Float>(cos(angle) * ringD, 0, sin(angle) * ringD)
        }
    }

    /// The switch flourish: a TILTED portal ring, deliberately distinct from
    /// the flat thinking ring so the two never read as the same event.
    private func updateSwitchParticles(progress: Float) {
        particleField.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        particleField.scale = .one
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

    /// Held by the host so the per-frame subscription driving `update` outlives
    /// the `RealityView` make closure.
    public var updateSubscription: EventSubscription?

    /// What gaze and pinch gestures target.
    public var tapTarget: Entity { sphereEntity }

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
