//
//  ParticleField.swift
//  HearthSpatial
//
//  The seam between the rig and whatever is swarming around it.
//
//  WHY THIS EXISTS AT ALL. Until now the persona's particles were 96
//  ModelEntities and four `update…Particles` methods living inside PersonaRig,
//  reached directly through `particleEntities[i].position`. That was fine while
//  there was exactly one field. Phase 4.5 adds a second -- embers off the
//  hearth-fire -- and a second field written the same way would have meant
//  eight update methods in one file, each of them free to touch the other's
//  arrays. The two fields do not merely LOOK different; they are built on
//  different machinery. Fireflies are choreographed: every dot's position is
//  stated each frame, which is the only way to draw a waveform or a ring. Embers
//  are SIMULATED: a `ParticleEmitterComponent` births them, buoyancy carries
//  them, and no one names where any particular ember is. A protocol is what
//  lets those two live side by side without either pretending to be the other.
//
//  WHY IT LIVES IN THE PACKAGE RATHER THAN IN THE VISION TARGET. The iOS client
//  is going to want the same fire. Today its orb is a SwiftUI Canvas, but the
//  path to a RealityView on the phone is already open -- that is why
//  HearthSpatial builds for iOS as well as visionOS -- and the whole point of
//  building that seam now is that the phone picks up `.fire` as a preset name
//  rather than as a port. Presets are shared vocabulary; a preset defined in an
//  app target is a preset the other target cannot say.
//
//  THE DIVISION OF LABOUR. The rig owns the clock, the turn state, the palette
//  and the audio level, and hands all of it over each frame in a `ParticleFrame`.
//  A choreography owns its entities and nothing else. It does not read the rig,
//  does not know what a persona is, and cannot decide when a turn begins -- the
//  same rule `FaceDirector` follows, and for the same reason: two things that
//  both decide when something happens will eventually disagree.
//

import Foundation
import RealityKit
import simd
import HearthCore

// MARK: - Which field

/// The persona's visual preset: which bead, which swarm.
///
/// This is deliberately ONE name for the whole look rather than separate
/// switches for the core and the field. A bead with embers, or a fire with
/// fireflies, are not styles anybody asked for; they are the states you get
/// when two settings drift apart. So the preset names a matched pair and the
/// rig applies both halves from it.
public enum ParticlePreset: String, Sendable, CaseIterable {
    /// The emissive bead in its firefly field. The default, and the fallback.
    ///
    /// It stays the default deliberately, and the reason is not sentiment. The
    /// bead is device-tested, shipped and understood, and it needs no Metal
    /// library, no compute pipeline and no `LowLevelMesh`. It is what a new
    /// user meets and what everybody falls back to when the flame's machinery
    /// is unavailable. Deleting it to make room for the fire would have left
    /// nothing to fall back TO.
    case fireflies

    /// The hearth-fire throwing embers. Phase 4.5's work.
    case fire
}

// MARK: - What the field is swarming around

/// The geometry a field arranges itself against.
///
/// Stated rather than assumed because the two presets orbit different things.
/// Fireflies orbit a 24cm bead. Embers rise off a flame three and a half times
/// that tall and slightly wider at the waist -- and if the flame's proportions
/// change, the embers have to follow without anybody editing a constant in two
/// files. So the rig measures its own geometry and hands the numbers over.
public struct ParticleWorld: Sendable, Equatable {
    /// The radius of the thing at the centre. For a bead, the sphere; for the
    /// fire, the flame's widest.
    public var coreRadius: Float
    /// How far out the field is allowed to reach, in rig units.
    public var maxDistance: Float
    /// How tall the visible core stands above the rig's origin. Zero for a
    /// bead, which is centred on it; the flame's visible top for the fire.
    public var coreHeight: Float

    /// Where the persona's FACE is, measured from the rig's origin.
    ///
    /// It is here because it is the one height on a persona that everything
    /// else is judged against. Whatever a swarm does, it does it around the
    /// eyes -- that is where a person is looking, and a plume centred anywhere
    /// else reads as belonging to a different object than the face does. The
    /// rig already computes this for the flame's face card; handing it over
    /// costs nothing and stops the number being guessed at twice.
    public var eyeHeight: Float

    /// How wide the core is AT `eyeHeight`, which is not the same as
    /// `coreRadius` on anything that is not a ball.
    ///
    /// A flame is a teardrop: widest low down, tapering to a point. A swarm
    /// sized to the widest part and placed at the eyes would be born well
    /// outside the silhouette at that height. So the rig asks the mesh how wide
    /// it actually is where the field is going to sit, and the field is sized
    /// from the answer. Same discipline as the spotlight's cone: derive from
    /// the shape, never restate it.
    public var waistRadius: Float

    public init(coreRadius: Float,
                maxDistance: Float,
                coreHeight: Float = 0,
                eyeHeight: Float = 0,
                waistRadius: Float? = nil) {
        self.coreRadius = coreRadius
        self.maxDistance = maxDistance
        self.coreHeight = coreHeight
        self.eyeHeight = eyeHeight
        // A ball is the same width everywhere, so the default is the honest
        // answer rather than a placeholder.
        self.waistRadius = waistRadius ?? coreRadius
    }
}

// MARK: - What the rig knows and the field does not

/// One frame's worth of everything a choreography needs and cannot work out
/// for itself.
///
/// A struct rather than seven arguments because it WILL grow: every time the
/// rig learns something new about the turn, the fields want to hear about it,
/// and a struct means that arrives as a field with a default rather than as a
/// signature change across every choreography.
public struct ParticleFrame: Sendable {
    /// The turn. The four beats every choreography has to answer for.
    public var state: PersonaState
    /// Seconds since the rig started animating. Monotonic, accumulated from
    /// frame deltas rather than read from a clock, so it cannot step backwards
    /// when the system time is adjusted.
    public var time: Float
    /// This frame's delta, in seconds.
    public var dt: Float
    /// The rig's eased motion amplitude for the current state.
    public var motion: Float
    /// The rig's eased spin rate, in revolutions per second.
    public var spin: Float
    /// Smoothed playback amplitude, 0 to 1. Meaningful while speaking; a small
    /// residue otherwise.
    public var level: Float
    /// The pinch-and-hold crossing, 0 to 1. Above zero it OVERRIDES the state:
    /// the flourish is the same event whatever turn it interrupts.
    public var transition: Float

    /// How much swarm this surface can afford, 0 to 1.
    ///
    /// A simulated field is the cheapest thing in the room to turn down and one
    /// of the more expensive to leave running: in the immersive house the
    /// embers share a frame with the proximity spotlight, the scene mesh and
    /// two Metal kernels. So the count is a POLICY of the surface rather than a
    /// constant of the preset, and it arrives here the same way every other
    /// budgeted effect arrives -- from `EffectBudget`, read once by the rig
    /// instead of queried by each effect.
    ///
    /// Choreographed fields ignore it: 96 dots is 96 dots, and dropping some
    /// would leave holes in a ring.
    public var density: Float

    public init(state: PersonaState,
                time: Float,
                dt: Float,
                motion: Float,
                spin: Float,
                level: Float,
                transition: Float,
                density: Float = 1) {
        self.state = state
        self.time = time
        self.dt = dt
        self.motion = motion
        self.spin = spin
        self.level = level
        self.transition = transition
        self.density = density
    }
}

// MARK: - The one rule every field obeys

// EVERYTHING IS LOCAL TO THE PERSONA. Never the room.
//
// A field hangs off the rig's root, and the rig travels: it slides across a
// volume, it is carried across a room by a pinch, it is scaled from a tennis
// ball to life size, and it crosses between two scenes entirely. Any quantity a
// field resolves against the ROOM is a quantity that stops meaning what it meant
// the moment any of that happens.
//
// This is not a style preference. It has already cost one bug: `EmberField`'s
// listening attraction was aimed at `.zero` without stating a simulation space,
// and RealityKit resolved it against the world -- so the embers flew at the
// point where the person happened to be standing when the immersive space
// opened. Nothing in the file could explain the behaviour, because the file was
// not the one deciding it. The vortex had the identical fault waiting silently,
// one strength value away from being seen.
//
// So, for any choreography added here:
//
//   - `fieldSimulationSpace` is `.local`. State it; the default is not a
//     promise.
//   - `particlesInheritTransform` is true, so a moved or resized persona brings
//     its swarm with it.
//   - `birthDirection` is `.local` or `.normal`, never `.world`. A persona who
//     has been turned throws sparks out of HIS top, not the room's.
//   - Positions are set on entities under `root`, never converted through
//     `nil`.
//
// The one thing a field is allowed to know about the room is what the rig hands
// it in `ParticleFrame` -- and the rig has already resolved that into the
// persona's own terms before it arrives.

// MARK: - The contract

/// A swarm that knows how to be four states.
///
/// Four is not negotiable and that is the whole point of naming the protocol
/// after the states rather than after the particles. Every preset has to have
/// an answer for resting, listening, thinking and speaking, because the persona
/// is always in one of them and a field that goes still during a turn reads as
/// a hang. Writing the preset means answering all four, and the compiler is not
/// what enforces it -- `update(_:)` switching on `frame.state` is -- so a
/// preset that has only drawn one of them should SAY so in its own comments
/// rather than quietly reusing another.
@MainActor
public protocol ParticleChoreography: AnyObject {
    /// Which preset this is. Lets the rig check what it is holding without a
    /// cast, and lets a debug overlay name it.
    static var preset: ParticlePreset { get }

    /// The field's own root. The rig parents this and toggles it; it never
    /// reaches inside.
    var root: Entity { get }

    /// Re-tint to a persona's colours. Called on every palette change, which is
    /// potentially every frame -- so implementations early-return when nothing
    /// moved rather than rebuilding materials.
    func apply(palette: PersonaPalette)

    /// The core changed shape underneath the field: a lantern lit, a flame
    /// resized. Cheap to call; implementations early-return on an equal world.
    func reshape(to world: ParticleWorld)

    /// One frame. Everything the field does happens here.
    func update(_ frame: ParticleFrame)
}

// MARK: - Shared arithmetic

/// Deterministic per-index pseudo-random in [0, 1).
///
/// Free rather than a method because both presets want it and neither should
/// own it. Seeded, allocation-free, and identical on every client -- which is
/// what makes a persona's field the SAME field everywhere rather than merely a
/// similar one. Two people looking at Sulivan in the same room see the same
/// dots in the same places, and that only holds if the randomness is a pure
/// function of the index.
public func particleNoise(_ i: Int) -> Float {
    let x = sin(Float(i) * 12.9898) * 43758.5453
    return x - floor(x)
}
