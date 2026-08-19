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

    // MARK: - Effect styles

    /// Which set of effects a non-corporeal persona wears.
    ///
    /// A PRESET, not a replacement, and that is the operator's instruction of
    /// 2026-08-18: the bead and its fireflies are what a brand-new house shows,
    /// and the flame is a second style beside it rather than the thing that
    /// took its place. A new user meets Sulivan as a warm bead in a swarm of
    /// fireflies; the hearth-fire is chosen.
    ///
    /// It matters beyond taste. The bead's look is device-tested, shipped and
    /// understood, and it is the fallback whenever the flame's machinery is
    /// unavailable -- no Metal, no compute pipeline, a metallib that did not
    /// make it into the bundle. Deleting it to make room for the new thing
    /// would have left nothing to fall back TO.
    public enum EffectStyle: String, Sendable, CaseIterable {
        /// The emissive bead with its firefly field. The default.
        case fireflies
        /// The hearth-fire with its embers. Phase 4.5's work.
        case ember
    }

    /// The style this persona is wearing. Changing it re-dresses the rig.
    ///
    /// `fireflies` by default, deliberately: a default is what everyone gets
    /// who never opens a setting.
    public var effectStyle: EffectStyle = .fireflies {
        didSet {
            guard effectStyle != oldValue else { return }
            applyEffectStyle()
        }
    }

    /// Put the current style on the rig, given who is standing there.
    ///
    /// Called when the style changes AND when the persona does, because both
    /// decide the answer: the ember style belongs to a bead, and a body wearing
    /// a fire is a different and much stranger idea. That is the same rule the
    /// bloom and the billboard follow -- effects are a property of the
    /// visualization KIND, never of a name.
    private func applyEffectStyle() {
        setLantern(effectStyle == .ember && !modelActive)
    }

    // MARK: - The lantern (phase 4.5 experiment)

    /// The bead as a paper lantern: a shell wearing an animated flame, with a
    /// point light at its exact centre throwing that warmth onto the real room.
    ///
    /// THE IDEA, and it is the operator's. `SurroundingsLight` is what puts a
    /// virtual light onto physical surfaces, and a POINT light is the right
    /// shape for a fire -- it sits somewhere and the room falls off around it,
    /// rather than aiming a cone. What a point light cannot do is carry a
    /// projected texture; only a spotlight can. So the pattern moves off the
    /// light and onto the SHELL: an alpha texture makes the sphere itself
    /// ripple, and the light inside makes the room warm.
    ///
    /// THE LIGHT MUST BE AT THE SPHERE'S CENTRE, exactly, which is why it is
    /// parented to the bead rather than positioned near it. Off-centre it stops
    /// being a bulb in a shade and becomes a lamp beside one -- and Valinor
    /// already learned the same lesson from the other end, where moving its
    /// projector two metres up meant nothing landed at all.
    ///
    /// KNOWN, BEFORE THE DEVICE SAYS IT: RealityKit point lights do not cast
    /// shadows. `Shadow` exists on `DirectionalLightComponent` and
    /// `SpotLightComponent` and there is no point-light equivalent. So the
    /// shell's alpha will NOT mask the light -- the pattern will be on the
    /// sphere, and what reaches the wall will be smooth warm light with no
    /// filaments in it. That is worth testing anyway: it answers whether the
    /// glow reaches a real wall at all, at what intensity, and whether the
    /// flame reads on the bead -- three things nothing else can tell us.
    private func setLantern(_ on: Bool) {
        guard on != (lanternLight != nil) else { return }
        guard on else {
            lanternLight?.removeFromParent()
            lanternLight = nil
            lanternTexture = nil
            lanternShell?.removeFromParent()
            lanternShell = nil
            flameMesh = nil
            showCoreAfterLantern()
            // Give the face and the halo back, now that nothing is standing in
            // for them.
            setOrbVisible(!modelActive)
            return
        }

        lanternTexture = AnimatedTexture(.fire)

        let light = Entity()
        light.name = "PersonaLantern"
        // Dead centre of the bead: a bulb inside a shade, not a lamp beside it.
        light.position = .zero
        light.components.set(PointLightComponent(color: lanternColor,
                                                 intensity: lanternLumens,
                                                 attenuationRadius: lanternReach))
        // The part that makes it touch the real room rather than only virtual
        // things. Without this the wall stays exactly as dark as it was.
        //
        // visionOS only, and that is the honest shape of it rather than an
        // oversight: there are no surroundings to light on a phone. The rest of
        // the lantern -- the shell, the flame, the bulb -- compiles and works
        // everywhere, so iOS gets a glowing sphere and no room glow, which is
        // exactly what iOS should get.
        #if os(visionOS)
        light.components.set(PointLightComponent.SurroundingsLight())
        #endif
        sphereEntity.addChild(light)
        lanternLight = light

        applyLanternMaterial()
        hideCoreForLantern()
        buildFlameFace()
        applyHoverEffect()
        // Take the face and the halo off, so what you are looking at is the
        // flame and nothing else. This is the "swap the mesh out" the test
        // asked for: same sphere, same size, entirely different surface.
        setOrbVisible(!modelActive)
    }

    /// A candle, from Apple's own table: 10-15 lumens over about a metre. The
    /// point-light DEFAULT is 26,963 lumens at ten metres, which is a floodlight
    /// -- three orders of magnitude between a hearth and a car park, and the
    /// kind of number that is much easier to look up than to guess at.
    ///
    /// SET FOR THE TEST, NOT FOR THE LOOK. Fourteen lumens over 1.2m is a
    /// candle and it could not be seen at all on the first run -- which is
    /// exactly what Apple's table says it should be, and useless for answering
    /// "does a point light reach a real wall". So the test runs at a table lamp
    /// and comes down once the answer is yes. Finding the ceiling first and
    /// then dimming is a shorter road than creeping up from nothing.
    /// Down from 7000 in two steps on the device. Valinor's 7000 was a
    /// SPOTLIGHT's number, spread over a cone and aimed away from the orb -- a
    /// point light spends the same lumens in every direction at once, from
    /// inside the thing you are looking at, so it was never the same figure.
    /// Still two orders above the candle Apple's table names, which is what a
    /// virtual light costs when it has to compete with passthrough of a lit
    /// room.
    public var lanternLumens: Float = 1500 {
        didSet { refreshLanternLight() }
    }
    public var lanternReach: Float = 10.0 {
        didSet { refreshLanternLight() }
    }

    /// The lantern's colour, for the light AND the flame.
    ///
    /// THE LIGHT'S colour only. The flame's own colour comes from the ramp
    /// texture, which is the whole point of having one.
    ///
    /// The hot pink is gone -- it did its job. It was there because a warm
    /// light in a warm room makes success and failure look identical, and once
    /// the wall was unmistakably lit there was nothing left for it to prove. A
    /// debug colour that ships is a debug colour nobody removed.
    ///
    /// Amber rather than white: this is the colour a fire throws, and it is the
    /// average of the ramp above the heart. When the light is eventually driven
    /// FROM the ramp on each frame, this becomes its resting value.
    public var lanternColor: UIColor = UIColor(red: 1.0, green: 0.55, blue: 0.22, alpha: 1) {
        didSet { refreshLanternLight(); applyLanternMaterial() }
    }

    /// The candle this is aiming AT, from Apple's own table, kept so the number
    /// to come back to is not lost.
    public static let candleLumens: Float = 14
    public static let candleReach: Float = 1.2

    private var lanternLight: Entity?
    private var lanternTexture: AnimatedTexture?
    private var lanternShell: ModelEntity?
    private var flameMesh: FlameMesh?
    private var flameFacePivot: Entity?

    /// The draw order for the things the lantern is made of.
    ///
    /// Transparency in RealityKit is sorted PER OBJECT, by distance, and two
    /// transparent objects that overlap get whichever answer that heuristic
    /// arrives at this frame -- which is why the face card flickered in and out
    /// of hiding the fire. A sort group replaces the heuristic with a stated
    /// order: the flame, then the face.
    private let lanternSortGroup = ModelSortGroup()

    /// The lantern's own clock, in seconds.
    ///
    /// ONE PHASE, FOUR CONSUMERS: the mesh's silhouette, the texture's inner
    /// structure, the light's colour and its intensity. They have to agree
    /// about when "now" is or the room gets four effects standing near each
    /// other rather than one fire. It is passed as an argument for the same
    /// reason `FaceDirector` takes `now` as one -- a clock read independently
    /// in four places is four clocks.
    private var lanternPhase: Float = 0

    /// Whether the bead is currently wearing the flame instead of its own face.
    private var lanternActive: Bool { lanternLight != nil }

    /// Put a changed brightness or reach onto a light that is already burning.
    private func refreshLanternLight() {
        guard let light = lanternLight,
              var component = light.components[PointLightComponent.self] else { return }
        component.intensity = lanternLumens
        component.attenuationRadius = lanternReach
        component.color = lanternColor
        light.components.set(component)
    }

    /// Build the flame: geometry for the silhouette, texture for the inside.
    ///
    /// The sphere shell that proved this works is gone. It could not stop being
    /// a sphere -- see `FlameMesh` -- so the shape moves to real geometry and
    /// the animated texture keeps doing the job it was always good at, which is
    /// the structure WITHIN the flame rather than its outline.
    private func applyLanternMaterial() {
        guard let texture = lanternTexture else { return }
        if flameMesh == nil {
            flameMesh = FlameMesh(radius: sphereRadius * 1.05,
                                  height: sphereRadius * 3.4)
        }

        // UNLIT, and this is the fix for a flame that came back pure white.
        //
        // It was a `PhysicallyBasedMaterial` with a white base colour and a
        // 7000-lumen point light sitting INSIDE it, centimetres away. A white
        // diffuse surface that close to a light that bright saturates: every
        // channel clips, and the emissive ramp was a small addition on top of
        // an already-blown-out white. Turning the emissive down would not have
        // helped, because the light was doing the damage.
        //
        // Fire does not receive light. It emits. An unlit material ignores the
        // room, ignores its own light, and draws exactly the texture it is
        // given -- which is what the flame wanted from the start, and it makes
        // the two-texture split unnecessary as well: unlit takes ONE colour
        // texture and uses its alpha for transparency, so colour and density
        // travel together.
        // `applyPostProcessToneMap: false` on Apple's own advice for unlit
        // materials: cheaper, and more accurate colours -- which matters when
        // the colours ARE the effect.
        var material = UnlitMaterial(color: .white, applyPostProcessToneMap: false)
        material.color = .init(tint: .white, texture: .init(texture.textureResource))
        material.blending = .transparent(opacity: 1.0)
        // BACK FACES CULLED AGAIN. Setting this to `.none` was a mistake and it
        // is the flame half of the transparency fault: with both sides drawn,
        // every pixel of the flame is TWO transparent surfaces from one mesh,
        // and RealityKit sorts transparency per object -- so the far wall of the
        // teardrop and the near wall have no defined order between them. What
        // that looks like is exactly what the device showed: dark regions where
        // the two layers disagree, and a body that seems to have solid parts
        // where nothing solid exists.
        //
        // A closed teardrop does not need its inside drawn. One layer, one
        // order, half the overdraw.
        material.faceCulling = .back

        guard let flameMesh else { return }
        if let shell = lanternShell {
            shell.model = ModelComponent(mesh: flameMesh.resource, materials: [material])
            return
        }
        let shell = ModelEntity(mesh: flameMesh.resource, materials: [material])
        shell.name = "PersonaFlame"
        // The flame draws FIRST, the face card second. See `lanternSortGroup`.
        shell.components.set(ModelSortGroupComponent(group: lanternSortGroup, order: 0))
        // The flame stands ON the bead's centre rather than around it: its own
        // profile already puts its base slightly below its origin, which is
        // where a flame meets whatever it is burning on.
        shell.position = .zero
        sphereEntity.addChild(shell)
        lanternShell = shell
    }

    /// Take the core away entirely and leave the flame standing on its own.
    ///
    /// THE THIRD ANSWER TO THE SAME QUESTION, and the sequence is worth keeping
    /// because each step was informative. The flame first went on the core's
    /// own material, which made the bead a flame-shaped HOLE. Then it moved to
    /// a shell over a lit core, and read as pink smears on a cream ball --
    /// nothing for the fire to be brighter than. Then the core went dark, which
    /// is Calcifer in a grate. Now the core goes away, which is Calcifer in the
    /// air: whatever the flame's texture does not draw is simply not there.
    ///
    /// The MODEL is removed, not the entity. `sphereEntity` carries the
    /// collision shape, the input target and the hover effect -- it is what
    /// gaze and pinch find -- and it is the flame shell's parent. Disabling it
    /// would take the fire and the ability to touch him with it.
    private func hideCoreForLantern() {
        guard let model = sphereEntity.model else { return }
        coreModel = model
        sphereEntity.model = nil
    }

    /// Put the face on a card in front of the flame instead of on a ball
    /// inside it.
    ///
    /// THE SPRITE, and it is the operator's -- traditional animation and game
    /// practice, where a character's features live on a flat card that always
    /// faces you rather than on the geometry. The face texture is already
    /// exactly what that needs: it is mostly transparent with opaque ink only
    /// where the features are, so a card wearing it shows EYES and nothing
    /// else. No new texture, no inverse mask to author -- the alpha it has
    /// always had is the mask.
    ///
    /// The sphere shell it replaces was sized to hug a bead. A flame is
    /// narrower than that almost everywhere and a different shape everywhere
    /// else, so the shell either poked through the fire or sat buried in it,
    /// and no scale fixes both at once.
    ///
    /// TWO ENTITIES, and the split is what makes "in front" mean anything. The
    /// pivot billboards; the card hangs at a fixed offset along the pivot's own
    /// forward. A card placed at a fixed offset in the FLAME's space would be in
    /// front of the fire from one direction and behind it from the other.
    ///
    /// Flat rather than curved, and that is not a shortcut: a card that always
    /// faces you is seen face-on by definition, so curvature across it would
    /// never be visible. It becomes worth having only if the face ever stops
    /// billboarding.
    private func buildFlameFace() {
        guard let faceTexture else { return }
        if flameFacePivot != nil { return }

        var material = UnlitMaterial(color: .white, applyPostProcessToneMap: false)
        material.color = .init(tint: .white, texture: .init(faceTexture.textureResource))
        material.blending = .transparent(opacity: 1.0)
        // A CUTOUT, not a blend, and this is the eyes half of the same fault.
        //
        // A blended transparent surface is still a SURFACE: its empty texels
        // take part in sorting even though they paint nothing, so a big mostly
        // empty card in front of the fire intermittently won the sort and hid
        // the flame behind its own rectangle. That is the flashing panel.
        //
        // A threshold makes RealityKit DISCARD anything below it rather than
        // blend it, so the empty part of the card stops existing as far as the
        // renderer is concerned. The cost is that the ink's edges go binary
        // instead of soft -- which is the right trade for eyes, and would be
        // the wrong one for the flame.
        material.opacityThreshold = 0.35
        // Both faces, because which way `BillboardComponent` presents an entity
        // is not something to be confident about from the desk: if it turns the
        // card's back to the viewer, culling makes it invisible and looks
        // exactly like a card that was never built.
        material.faceCulling = .none

        // WIDER THAN TALL, and that is the fix for eyes that came out as two
        // narrow tally marks.
        //
        // The face texture was authored to be worn by a SPHERE. The kernel
        // draws it in longitude and latitude, and wrapping that onto a curved
        // front hemisphere stretches it horizontally -- so the eyes are drawn
        // narrow on purpose, and the sphere widens them back. A flat card does
        // no such widening, so it shows the unwrapped drawing exactly as
        // stored: correct height, far too thin.
        //
        // Undoing it in the card's proportions rather than in the kernel keeps
        // the phone and the headset drawing the same face from the same
        // numbers, which is the whole reason `FaceDirector` is shared.
        let card = ModelEntity(mesh: .generatePlane(width: sphereRadius * Self.flameFaceWidth,
                                                    height: sphereRadius * Self.flameFaceHeight),
                               materials: [material])
        card.name = "PersonaFlameFace"
        // After the flame, always. Its position already puts it in front; this
        // says so to the renderer rather than leaving it to be worked out from
        // two transparent objects' origins.
        card.components.set(ModelSortGroupComponent(group: lanternSortGroup, order: 1))
        // Forward of the pivot, along the direction the pivot is turned to.
        card.position = SIMD3<Float>(0, 0, sphereRadius * Self.flameFaceLift)

        let pivot = Entity()
        pivot.name = "PersonaFlameFacePivot"
        pivot.position = SIMD3<Float>(0, sphereRadius * Self.flameFaceRise, 0)
        pivot.components.set(BillboardComponent())
        pivot.addChild(card)

        sphereEntity.addChild(pivot)
        flameFacePivot = pivot
        // Said out loud: "no eyes at all" has three possible causes -- the card
        // was not built, it was built facing away, or it is buried in the fire
        // -- and only the first one can be ruled out from here.
        log.notice("flame face card built")
    }

    private func removeFlameFace() {
        flameFacePivot?.removeFromParent()
        flameFacePivot = nil
    }

    /// The face card's proportions, how high up the flame it sits, and how far
    /// clear of the fire it floats.
    ///
    /// Bigger than the first attempt as well as wider. The card's background is
    /// fully transparent, so growing it costs nothing visually and is the
    /// simplest way to make a face that occupies a small part of its texture
    /// occupy a large part of the flame.
    private static let flameFaceWidth: Float = 3.57
    private static let flameFaceHeight: Float = 2.42
    private static let flameFaceRise: Float = 0.25
    /// How far the face floats clear of the fire.
    ///
    /// Brought back in from 1.45 now that the draw order is STATED rather than
    /// guessed. That number existed to keep the card physically clear of the
    /// flame, because two transparent surfaces in the same space sorted by
    /// luck; the sort group and the cutout threshold solve that properly, so
    /// the distance can go back to being an aesthetic choice. A face that
    /// hovers a hand's width in front of a flame reads as a mask on a stick.
    ///
    /// Out to 1.75 and back to 1.0 across two device runs: 0.95 sat the eyes ON
    /// the fire, 1.75 floated them clear of it.
    ///
    /// Expressed in RADII rather than centimetres on purpose -- the flame
    /// scales with the persona, so a fixed offset would be a face pressed
    /// against a tennis-ball Sulivan and a face stranded in front of a large
    /// one. Which also means a correction given in centimetres has to be
    /// converted through whatever size he was at the time, and this one assumed
    /// the room's own bead scale. If the eyes are still wrong, say it in
    /// radii or say what size he was.
    private static let flameFaceLift: Float = 1.0

    /// Give the bead its body back when the lantern goes out.    /// Give the bead its body back when the lantern goes out.
    private func showCoreAfterLantern() {
        removeFlameFace()
        applyHoverEffect()
        guard let model = coreModel else { return }
        sphereEntity.model = model
        coreModel = nil
        configureSphereMaterial()
    }

    /// The bead's own mesh and material, parked while the flame stands alone.
    private var coreModel: ModelComponent?

    /// Keep the flame moving, and the light breathing with it.    /// Keep the flame moving, and the light breathing with it.
    ///
    /// The flicker is the whole reason this is not just a warm lamp. A fire's
    /// signature from across a room is not its shape -- it is that the light on
    /// the walls is never still.
    private func tickLantern(dt: Float) {
        guard let texture = lanternTexture, let light = lanternLight else { return }
        lanternPhase += dt
        texture.tick(deltaTime: dt)
        flameMesh?.update(phase: lanternPhase)
        guard var component = light.components[PointLightComponent.self] else { return }
        component.intensity = lanternLumens * (0.75 + 0.5 * texture.flicker())
        light.components.set(component)
    }

    /// Which axes a persona is allowed to turn on when she is facing you.
    ///
    /// `BillboardComponent` was the first answer and it is the wrong one for
    /// anything with feet. It has no axis constraint: it turns the entity to
    /// the viewer on every axis, so a persona shrunk to a desk toy and stood on
    /// the floor TILTS BACK to look up at you. On a bead nobody would notice.
    /// On a body it is the head-turning scene from a horror film, which is a
    /// long way from "she is facing me".
    ///
    /// Roll is deliberately absent rather than merely unused. A look-at can
    /// only recover roll from the viewer's own head tilt, which is not
    /// something this app has or should ask for -- so offering the option would
    /// be offering a switch that does nothing.
    public struct FacingAxes: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// Turn about the vertical -- which way she is facing.
        public static let yaw = FacingAxes(rawValue: 1 << 0)
        /// Tilt to look up or down at the viewer.
        public static let pitch = FacingAxes(rawValue: 1 << 1)

        /// Feet on the floor and head level: turns to face you, never leans.
        /// The right answer for anything with a body.
        public static let upright: FacingAxes = [.yaw]
        /// Fully turned to the viewer, the way a flat panel wants to be.
        public static let free: FacingAxes = [.yaw, .pitch]
    }

    /// How much of the viewer's direction the persona is allowed to take.
    ///
    /// `.upright` because the personas who need this have bodies. A bead could
    /// take `.free` harmlessly, and that is exactly the kind of per-persona
    /// difference this being a property rather than a constant is for.
    public var facingAxes: FacingAxes = .upright

    /// Where the person watching is, and which way they are looking.
    ///
    /// The whole device transform rather than just its translation, because the
    /// forward vector is in it and the next things that want this -- spawning
    /// something in front of you, a persona who walks to where you are looking
    /// -- want the direction as much as the point. Turning to face someone only
    /// needs the point, so that is all this file reads today.
    ///
    /// A CLOSURE, supplied by the host, for two reasons. HearthSpatial compiles
    /// for iOS and must not import ARKit to do it; and the pose is the room's
    /// to fetch, since it is the room that already runs a world-tracking
    /// provider and already holds the authorisation for one.
    ///
    /// This is the head pose, which is worth naming plainly rather than
    /// hiding: `WorldTrackingProvider.queryDeviceAnchor(atTimestamp:)` is the
    /// documented way to have something follow a person's view, and it is
    /// deliberately gated behind world sensing. It reaches the rig's
    /// orientation and goes no further, and it is never stored.
    ///
    /// Nil, or a nil return, simply means she does not turn this frame. A
    /// persona facing slightly the wrong way is a much smaller failure than one
    /// that stops being drawn.
    public var viewerTransform: (@MainActor () -> simd_float4x4?)?

    /// Keep the persona turned toward whoever is looking at her.
    ///
    /// TWO MECHANISMS, chosen by what is on stage, which is the same rule the
    /// effects follow: a bead is not grounded in anything, so it takes
    /// `BillboardComponent` and turns however it likes -- there is no wrong way
    /// up for a floating light, and the free version is cheaper and runs out of
    /// process. A body has feet, and gets the constrained turn below.
    ///
    /// The reader panel is the bead's case in a different shape: a page tilting
    /// to face you is what a page should do.
    ///
    /// A thing you have put on your desk should be facing you, and always being
    /// right beats a gesture to make it right.
    ///
    /// IT TAKES THE ORIENTATION OVER. While this is on, `update` writes the
    /// rig's rotation from the viewer instead of from `behaviour.yaw` -- the
    /// director's turn would otherwise be computed, assigned and discarded.
    /// What is lost with it is her turning to look at things, which for a
    /// persona always facing you was never visible anyway.
    ///
    /// Off by default. The volume has one right way to be looked at, which is
    /// out of the front of the box.
    ///
    /// A FLAG RATHER THAN A FIXED COMPONENT, on purpose and ahead of need. When
    /// motion is picked back up, a persona who crosses the room has to face the
    /// way she is WALKING -- a figure gliding sideways across a floor while
    /// staring at you is the uncanny version of this feature, not a subtler
    /// one. So the director will want this off for the length of a move and
    /// back on when she settles, and the switch is here now so that discovering
    /// it later is a line of code rather than an unpicking.
    public var facesViewer = false {
        didSet { refreshFacing() }
    }

    /// Put the right facing mechanism on the rig for whoever is standing there.
    ///
    /// Called when the flag changes AND when the persona does, because a switch
    /// from Sulivan to Selene changes which mechanism is correct -- and a
    /// billboard left behind on a body is precisely the tilt this was all
    /// written to avoid.
    private func refreshFacing() {
        if facesViewer && !modelActive {
            rootEntity.components.set(BillboardComponent())
        } else {
            rootEntity.components.remove(BillboardComponent.self)
        }
    }

    /// Turn to the viewer, on the axes she is allowed to turn on.
    ///
    /// HER FRONT IS +Z, which is the one assumption here worth knowing about.
    /// It is not arbitrary: at yaw zero she faces out of the volumetric
    /// window, and the person looking into that window is on the +Z side. If a
    /// persona ever ends up facing away, this is the sign to flip and nothing
    /// else -- a model authored backwards is corrected by `rotationY` from its
    /// own config, which is a different knob in a different place.
    private func faceViewer() {
        guard let device = viewerTransform?() else { return }
        let viewer = SIMD3<Float>(device.columns.3.x, device.columns.3.y, device.columns.3.z)
        let toViewer = viewer - rootEntity.position(relativeTo: nil)

        let flat = SIMD2<Float>(toViewer.x, toViewer.z)
        guard simd_length(flat) > 0.0001 else { return }
        let yaw = facingAxes.contains(.yaw) ? atan2(toViewer.x, toViewer.z) : 0

        var pitch: Float = 0
        if facingAxes.contains(.pitch) {
            let distance = simd_length(toViewer)
            if distance > 0.0001 { pitch = asin(toViewer.y / distance) }
        }

        rootEntity.orientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            * simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
    }

    /// Capture for a pinch in progress, in METRES, so a resize is a delta from
    /// the size the gesture started at rather than a compounding multiplication
    /// of whatever the last frame produced.
    private var gestureSize: Float?

    /// How big the persona currently IS, in the host's metres -- her height if
    /// she has a body, the bead's diameter if she does not.
    ///
    /// One number for two very different things, which is the same trick
    /// `crownHeight` plays and for the same reason: a host resizing a persona
    /// should not have to know which kind it has.
    public var presentedSize: Float {
        modelActive ? crownHeight : sphereRadius * 2 * max(rootEntity.scale.x, 0.0001)
    }

    /// Set how big the persona is, in metres, through whichever knob actually
    /// governs it.
    ///
    /// AND THEY ARE DIFFERENT KNOBS, which is the whole reason this method
    /// exists rather than a caller writing a scale. `layoutPersonaHosts` sets
    /// `modelHost.scale = modelPresentationScale / rigScale`, deliberately, so
    /// that a model keeps its own size while the bead changes with the host --
    /// which means the rig scale is CANCELLED for a model and `setRigScale`
    /// moves a corporeal persona not at all. A pinch routed through it looks
    /// broken and is not: it is asking the wrong knob.
    ///
    /// So: a body is sized by `modelPresentationScale`, a bead by the rig
    /// scale, and the caller says how tall it wants her in metres.
    public func resize(to metres: Float) {
        // Clamped HERE rather than only in the gesture, because this is also
        // the restore path -- and a size that arrives from a store is exactly
        // the one nobody watched being produced. A bad number written straight
        // to the knob is a persona you cannot find in order to fix.
        let range = modelActive ? Self.modelHeightRange : Self.beadSizeRange
        let metres = min(max(metres, range.lowerBound), range.upperBound)
        if modelActive {
            // Her authored height, recovered from what she currently measures,
            // rather than assumed from `modelLifeHeight`. The fit already
            // happened and the measurement knows about it.
            let unit = max(crownHeight / max(modelPresentationScale, 0.0001), 0.0001)
            modelPresentationScale = metres / unit
        } else {
            setRigScale(metres / max(sphereRadius * 2, 0.0001))
        }
    }

    /// Resize by however much the pinch has spread since it began.
    ///
    /// Sets a TARGET rather than the size itself. A magnification read straight
    /// onto the knob every frame is as steady as the hand reporting it, and a
    /// two-handed pinch in mid-air is not steady at all -- the persona judders
    /// while it grows. See `tickSize`.
    public func magnify(by magnification: Float) {
        if gestureSize == nil { gestureSize = presentedSize }
        guard let start = gestureSize else { return }
        let range = modelActive ? Self.modelHeightRange : Self.beadSizeRange
        targetSize = min(max(start * max(magnification, 0.0001),
                             range.lowerBound), range.upperBound)
    }

    /// True while a pinch-to-resize is in progress, so a host can keep other
    /// gestures off her while it is. A two-handed pinch also reads as a drag,
    /// and a persona who slides across the room while being resized is being
    /// asked two things at once.
    public var isResizing: Bool { gestureSize != nil }

    /// Let go of a resize. The TARGET is kept: the ease is allowed to finish
    /// after your fingers have opened, which is what makes the last frame of a
    /// gesture look like the end of a movement rather than a stop.
    public func endGesture() {
        gestureSize = nil
    }

    /// Ease the persona toward the size the pinch asked for.
    ///
    /// Frame-rate independent, and that matters more here than it looks: a
    /// fixed per-frame fraction eases at one speed at 90Hz and another when the
    /// room is busy, so the feel of the gesture would change with the scene.
    /// Raising the retention to a power of the frame's share of 60Hz keeps the
    /// time constant fixed in SECONDS instead.
    private func tickSize(dt: Float) {
        guard let target = targetSize else { return }
        let current = presentedSize
        guard abs(target - current) > 0.0005 else {
            resize(to: target)
            targetSize = nil
            return
        }
        let blend = 1 - pow(Self.sizeRetention, max(dt, 0.0001) * 60)
        resize(to: current + (target - current) * blend)
    }

    /// How much of the gap to the target survives each 60Hz frame. Lower is
    /// snappier; this is roughly a tenth of a second to settle, which reads as
    /// attached to the hand rather than as lag.
    private static let sizeRetention: Float = 0.75

    private var targetSize: Float?

    /// What a persona may be pinched to, as PHYSICAL SIZES rather than as
    /// fractions of a scale.
    ///
    /// Fractions were the first attempt and they were wrong twice over. A
    /// single 0.3 floor meant a bead whose host had already set 0.5 could only
    /// shrink to a grapefruit, and meant nothing at all for a body whose size
    /// does not come from that scale. Metres are what the person in the room is
    /// actually judging, so metres are what the clamp is written in.
    ///
    /// The numbers are the operator's, given on device on 2026-08-18: the bead
    /// goes down to a TENNIS BALL, and the body to a shade over a traditional
    /// doll -- small enough to stand on a desk, which is the point of being
    /// able to shrink her at all.
    public static let beadSizeRange: ClosedRange<Float> = 0.067...0.60
    public static let modelHeightRange: ClosedRange<Float> = 0.34...2.0

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
    /// THE SIZE OF THE BEAD, and no longer generous.
    ///
    /// It was 0.46 against a sphere of 0.24 -- nearly double, on the reasoning
    /// that a gaze target the size of the bead is one people miss. In a volume
    /// that cost nothing. In a ROOM it is a metre-wide invisible ball around a
    /// palm-sized light: it held Sulivan half a metre off the floor, because
    /// what met the floor was the collider rather than the sphere, and it made
    /// him feel like he was bumping into things that were not there.
    ///
    /// A collider that is not the shape of the thing is a lie the room tells,
    /// and in a room the room is the authority. If gaze targeting suffers, the
    /// answer is a small margin here -- not a second sphere.
    private var tapTargetRadius: Float { sphereRadius }
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
            // A billboard belongs to a bead. She has feet now, and so does the
            // fire she is not wearing.
            self.refreshFacing()
            self.applyEffectStyle()
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
        // THE COLLIDER GOES WITH THE MODEL.
        //
        // `unload` takes the mesh out of the model host; it does not take the
        // components off the host itself. Leaving them left a person-sized,
        // invisible collision box standing exactly where the persona is, with
        // an InputTargetComponent on it -- so switching from Selene back to
        // Sulivan gave you a bead you could see and could not touch. Every
        // pinch aimed at it landed on the ghost of her instead, and neither a
        // tap nor a hold ever reached the target the gesture was aimed at.
        //
        // The other direction worked and hid the bug: the bead is DISABLED
        // under a model, and a disabled entity does not hit-test.
        //
        // Same fault as the un-fitted collision box that once swallowed every
        // pinch in the volume, and the same lesson: a collider outlives what it
        // was measured from unless something takes it away.
        clearModelCollision()
        guard modelActive else { return }
        modelActive = false
        setOrbVisible(true)
        // Back to a bead, which may billboard freely -- and may burn.
        refreshFacing()
        applyEffectStyle()
    }

    private func clearModelCollision() {
        #if os(visionOS)
        modelHost.components.remove(CollisionComponent.self)
        modelHost.components.remove(InputTargetComponent.self)
        modelHost.components.remove(HoverEffectComponent.self)
        #endif
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
        // The lantern REPLACES the bead's own surface, so the two things drawn
        // on top of it come off with it. The face shell sits at 1.02 of the
        // sphere's radius -- it is a second sphere covering the first -- so a
        // flame applied underneath is perfectly hidden by a face. That is why
        // swapping the material alone changed nothing you could see.
        glowBillboard?.isEnabled = visible && isAlive && !realBloomActive && !lanternActive
        // The sphere face is off while the flame burns: the card in front of
        // the fire is wearing the same texture, and two faces is one too many.
        faceShell?.isEnabled = visible && isAlive && !lanternActive
        lanternShell?.isEnabled = visible && isAlive && lanternActive
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

    /// How far the persona reaches to either SIDE of her own origin, in the
    /// host's metres.
    ///
    /// The companion to `crownHeight`, and it exists for the same reason: work
    /// hung on the persona has to be placed clear of her, and "clear of her"
    /// is a different number for a bead the size of a plum and a person at life
    /// size. A host that guessed one number would have it right for one of them.
    ///
    /// It matters more than it sounds. Her collision box spans her whole body,
    /// so anything parented inside that span is not merely overlapping her --
    /// it is UNREACHABLE, because a pinch aimed at it lands on her instead.
    public var halfWidth: Float {
        let rigScale = max(rootEntity.scale.x, 0.0001)
        guard modelActive else { return sphereRadius * rigScale }
        let nominal = modelLifeWidth * modelPresentationScale * 0.5
        guard modelFramed else { return nominal }
        let bounds = modelHost.visualBounds(relativeTo: rootEntity)
        guard bounds.extents.x > 0.0001 else { return nominal }
        return bounds.extents.x * 0.5 * rigScale
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
        // Only ever while a model is actually up. A late `onFramed` from a
        // loader whose persona has already been switched away from would
        // otherwise put the box back after the teardown removed it.
        guard modelActive else { return }
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
            // The core paints itself as usual -- UNLESS the lantern is lit, in
            // which case the core's job is to be the dark the flame is seen
            // against. See `dressCoreForLantern`.
            if !lanternActive {
                sphereMaterial.emissiveColor = .init(color: rigColor(glow))
                sphereMaterial.emissiveIntensity = intensity * 1.3 + 0.3 * pulse
                sphereMaterial.baseColor = .init(tint: rigColor(sphereBaseColor,
                                                                alpha: sphereAlpha))
                sphereEntity.model?.materials = [sphereMaterial]
            }

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
        // How big she is, eased toward whatever the last pinch asked for.
        tickSize(dt: dt)
        tickLantern(dt: dt)

        // The rig turns, which is what makes the face look at anything: the
        // face is painted on the front of a shell that does not billboard, so
        // it looks wherever the rig is pointed.
        //
        // One author for the orientation, whichever it is. Facing the viewer
        // and performing the director's own turn are the same field, and a
        // frame that wrote both would show whichever ran second.
        if facesViewer && modelActive {
            faceViewer()
        } else if !facesViewer {
            rootEntity.orientation = simd_quatf(angle: behavior.yaw,
                                                axis: SIMD3<Float>(0, 1, 0))
        }
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
        applyHoverEffect()
        #endif
    }

    /// The gaze feedback, which is not one effect for every persona.
    ///
    /// THE WHITE FLASH. visionOS draws a hover highlight wherever you look, out
    /// of process, and the default is a bright neutral one -- which on a bead
    /// is exactly right and on a FLAME is a white sheet dropping over the fire
    /// at random. It looked like a rendering fault and it is the system telling
    /// you, correctly, that this thing can be tapped.
    ///
    /// SO IT IS RESTYLED RATHER THAN SUPPRESSED. Moving the collider to an
    /// invisible proxy would silence it, and would also silence the one signal
    /// that the persona is interactive at all -- a real loss for the sake of an
    /// artefact. A warm, weak spotlight style says the same thing in the fire's
    /// own language: look at him and he brightens, which is what a fire does
    /// when you lean toward it.
    private func applyHoverEffect() {
        #if os(visionOS)
        guard lanternActive else {
            sphereEntity.components.set(HoverEffectComponent())
            return
        }
        sphereEntity.components.set(HoverEffectComponent(.spotlight(
            .init(color: lanternColor, strength: Self.lanternHoverStrength))))
        #endif
    }

    /// Weak on purpose: enough to notice, not enough to read as a flash. If it
    /// still announces itself on device, this is the number, and zero is a
    /// legitimate answer.
    private static let lanternHoverStrength: Float = 0.35

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
