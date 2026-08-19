//
//  EmberField.swift
//  HearthSpatial
//
//  The fire preset's swarm: embers coming off the hearth-flame.
//
//  THE ONE THING TO UNDERSTAND BEFORE READING ANY NUMBER BELOW. This file works
//  the opposite way round to FirefliesField, and the difference is not style.
//  Fireflies are CHOREOGRAPHED -- 96 named entities whose positions are stated
//  every frame, which is the only way to draw a ring or spell out a waveform.
//  Embers are SIMULATED. A `ParticleEmitterComponent` births them, buoyancy and
//  turbulence carry them, and nothing in this file ever knows where any
//  particular ember is. That is correct for fire: the whole character of an
//  ember is that nobody placed it. It also means the code is a CONFIGURATION
//  rather than a loop, and the per-frame work is close to nothing.
//
//  WHICH LEADS TO THE RULE THIS FILE LIVES BY: the emitter is authoritative.
//  When the ember preset is on, `update(_:)` does not push particles anywhere.
//  It hands the simulator a new set of rules when the turn changes and then
//  gets out of the way. There is no halfway house where the rig nudges an
//  emitter's output, because a simulated particle that something else is also
//  moving belongs to neither system and looks like neither.
//
//  AND ONE CONSEQUENCE WORTH STATING. `ParticleEmitterComponent` is a VALUE
//  type: changing a property means reassigning the whole component, which
//  restarts nothing but is not free. So this field is EDGE-TRIGGERED. It writes
//  a configuration when the state changes, not every frame, which is why
//  `appliedState` exists and why the per-frame path early-returns for the vast
//  majority of frames.
//
//  STATUS: idle is drawn. Listening, thinking and speaking are named below and
//  currently hold the idle configuration -- deliberately and visibly, so the
//  first device pass is judging one thing. See `tasks/vision-phase-4.md`.
//

import Foundation
import RealityKit
import simd
import HearthCore

#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class EmberField: ParticleChoreography {
    public static let preset: ParticlePreset = .fire

    public let root = Entity()

    /// The one entity carrying the emitter. Kept separate from `root` so the
    /// rig can enable and disable the field without disturbing where the
    /// emitter sits relative to the flame.
    private let emitter = Entity()

    private var world: ParticleWorld
    private var palette: PersonaPalette

    /// The configuration currently written into the component. Nil forces the
    /// next update to write one.
    private var appliedState: PersonaState?

    public init(world: ParticleWorld, palette: PersonaPalette) {
        self.world = world
        self.palette = palette
        root.name = "EmberField"
        emitter.name = "EmberEmitter"
        root.addChild(emitter)
        placeEmitter()
    }

    // MARK: - Where the embers come from

    /// Put the emitter at the persona's EYES rather than up the flame.
    ///
    /// It sat at 42% of the flame's visible top, on the reasoning that embers
    /// peel off a fire's shoulders. That is true of a bonfire and wrong here,
    /// because this fire has a FACE. Everything the eye is doing is happening
    /// at the face card's height, and a plume whose source is a third of a
    /// metre above it reads as a separate object passing behind him. Centring
    /// it on the eyes puts the fire and the persona in the same place.
    ///
    /// The height is not restated: it comes from the rig, which reads it from
    /// the same constant the face card is positioned by, so the two cannot
    /// drift apart.
    private func placeEmitter() {
        emitter.position = SIMD3<Float>(0, world.eyeHeight, 0)
    }

    /// How far past the flame's own skin the embers are born, at the height
    /// they are born at.
    ///
    /// WIDER THAN THE FLAME, ON PURPOSE, and this is a correction. It was 0.62
    /// of the flame's WIDEST radius, applied at a height where the flame is not
    /// its widest -- which put every ember inside the silhouette, where they
    /// were hidden by the very thing they were supposed to be coming off.
    /// Embers you cannot see are not embers.
    ///
    /// Now the rig measures the flame's radius at exactly the height the
    /// emitter sits, and this pushes the birth shell slightly outside it. Just
    /// outside: a fire's embers come off its edge, and a shell much wider than
    /// this stops reading as a fire at all and starts reading as a ring around
    /// one.
    private static let birthSpread: Float = 1.15

    // MARK: - ParticleChoreography

    public func apply(palette newPalette: PersonaPalette) {
        guard newPalette != palette else { return }
        palette = newPalette
        // The ember's colour is the persona's, so a palette change has to
        // rewrite the component. Clearing the applied state is how, and it
        // costs one configuration write rather than a special path.
        appliedState = nil
    }

    public func reshape(to newWorld: ParticleWorld) {
        guard newWorld != world else { return }
        world = newWorld
        placeEmitter()
        appliedState = nil
    }

    public func update(_ frame: ParticleFrame) {
        // THE EARLY RETURN IS THE POINT. Ninety-nine frames in a hundred there
        // is nothing to do: the simulator is already running the right rules.
        guard frame.state != appliedState else { return }
        appliedState = frame.state

        switch frame.state {
        case .resting:   configure(.resting)
        // NOT YET DRAWN. Each of these gets its own configuration in the next
        // pass -- listening draws the embers inward and holds them, thinking
        // spins them into a vortex, speaking bursts on the playback amplitude,
        // all of which the emitter can express through `attractionStrength`,
        // `vortexStrength` and `burst()`. Until then they hold idle, ON PURPOSE
        // and visibly, so the first device pass is judging one configuration
        // rather than four half-guesses that muddy each other.
        case .listening: configure(.resting)
        case .thinking:  configure(.resting)
        case .speaking:  configure(.resting)
        }
    }

    // MARK: - The configurations

    /// Idle: a slow, sparse rise. The fire is burning and nobody is talking to
    /// it.
    ///
    /// The numbers are chosen against a flame roughly 25cm wide and 80cm tall
    /// -- Sulivan at his full volumetric size -- and every one of them is a
    /// fraction of `world` rather than an absolute, so a Sulivan pinched down
    /// to a desk toy gets embers in proportion instead of a shower of boulders.
    private func configure(_ state: PersonaState) {
        var component = ParticleEmitterComponent()

        // Born on the skin of a sphere, leaving along its normal. This is the
        // shape that reads as "coming off a fire" rather than "shot from a
        // point": embers leave in every direction at once, and the ones aimed
        // down simply lose to buoyancy a moment later, which is exactly what
        // real ones do.
        component.emitterShape = .sphere
        // SIZE, NOT RADIUS. RealityKit's other `size` properties are full
        // extents along each axis, so a birth sphere as wide as the flame is a
        // diameter -- and reading it as a radius is the likeliest explanation
        // for how far inside the silhouette the first pass landed. If the
        // embers now start too far out, this factor of two is the first
        // suspect and halving it is the whole fix.
        component.emitterShapeSize = SIMD3<Float>(
            repeating: world.waistRadius * 2 * Self.birthSpread)
        component.birthLocation = .surface
        component.birthDirection = .normal

        // Slow, but not as slow as the first pass. An ember's speed comes from
        // the air around it, not from a launch, and anything much faster reads
        // as sparks off a grinder -- but too slow and buoyancy wins immediately,
        // which is what kept the plume as narrow as the flame. The outward
        // travel has to survive long enough to get clear.
        component.speed = 0.085 * Self.sizeFactor(world)
        component.speedVariation = 0.070 * Self.sizeFactor(world)

        // PARTICLES FOLLOW THE PERSONA. The alternative -- leaving embers
        // behind in world space as Sulivan is carried across a room -- is more
        // physical and genuinely lovely, and it is the wrong trade for the
        // first pass: it also means the plume does not scale when he is pinched
        // down to a tennis ball, and a fire whose embers are the wrong size
        // reads as broken in a way a fire that does not trail does not. Worth
        // revisiting on device once the size question is answered.
        component.particlesInheritTransform = true
        component.simulationState = .play
        component.isEmitting = true

        var main = component.mainEmitter

        // Sparse. Fewer, better-seen embers beat a haze -- the same lesson the
        // firefly twinkle taught, where a hundred dots at a tenth opacity read
        // as clutter and a third of them at full opacity read as fireflies.
        main.birthRate = 26
        main.birthRateVariation = 10

        // Long enough to travel a flame-height and a bit past it. Embers that
        // die at the crown look like the flame has a lid.
        main.lifeSpan = 2.4
        main.lifeSpanVariation = 1.1

        main.size = 0.0075 * Self.sizeFactor(world)
        main.sizeVariation = 0.004 * Self.sizeFactor(world)
        // Embers SHRINK as they burn out. Fading alone leaves ghosts of the
        // original size hanging in the air.
        main.sizeMultiplierAtEndOfLifespan = 0.15

        // BUOYANCY, which is the whole reason a `.normal` birth direction works
        // here. Embers leave the flame in every direction and are then all bent
        // upward by the same rising column of air. Damping is what makes that
        // bend look like air rather than gravity: they lose their initial
        // speed, and what remains is the lift.
        main.acceleration = SIMD3<Float>(0, 0.062 * Self.sizeFactor(world), 0)
        // Damping down from 0.55: it was bleeding off the outward speed before
        // the ember had cleared the flame, so every one of them turned upward
        // while still inside it. Less damping is what lets the plume open.
        main.dampingFactor = 0.32
        // And a much wider cone off the birth normal. At 0.30 the embers left
        // the surface almost perpendicular and in near-lockstep, which reads as
        // a shell rather than a swarm.
        main.spreadingAngle = 0.85

        // The wander. A fire's air is turbulent, and embers that rise in
        // straight lines look like a fountain. Kept low: strong noise turns a
        // plume into a snowstorm.
        main.noiseStrength = 0.125 * Self.sizeFactor(world)
        // Scale DOWN as strength goes up: a lower number is a larger swirl, and
        // large slow swirls are what carry a plume sideways. Small strong ones
        // just make every ember jitter in place.
        main.noiseScale = 1.15
        main.noiseAnimationSpeed = 0.24

        main.opacityCurve = .easeFadeOut
        // Slight streaking along the direction of travel. Embers are seen as
        // short traces rather than points, because they move while the eye
        // integrates -- and because a camera would show the same.
        main.stretchFactor = 0.35

        // ADDITIVE, AND IT SOLVES THE PROBLEM THAT COST THIS PROJECT DAYS.
        // Every transparency artefact on the flame came from sorting: two
        // transparent surfaces with no defined order between them. Additive
        // blending is ORDER-INDEPENDENT -- adding light to light gives the same
        // answer whichever comes first -- so the embers can be `.unsorted` and
        // still be correct. It is also what fire does: light adds.
        main.blendMode = .additive
        main.sortOrder = .unsorted
        // Fire is not lit by the room; it lights the room. Same reasoning that
        // made the flame's own material unlit.
        main.isLightingEnabled = false

        main.color = emberColor(for: state)
        // Above 1 the ember holds its hot colour for most of its life and cools
        // late, which is how a real one behaves: the colour change is the last
        // thing that happens before it goes out.
        main.colorEvolutionPower = 1.6

        component.mainEmitter = main
        // Value type: the component has to be set back, not merely mutated.
        emitter.components.set(component)
    }

    // MARK: - Colour

    /// The ember's hot-to-cold ramp for a turn.
    ///
    /// The HOT end is the persona's own accent for the state, which is what
    /// ties the fire to whoever is wearing it and makes the turn readable from
    /// across a room: the embers warm toward the speaking accent and cool
    /// toward the thinking one, without a single extra wire. The COLD end is
    /// fixed, because a dying ember is the same deep red whatever was burning.
    private func emberColor(for state: PersonaState)
    -> ParticleEmitterComponent.ParticleEmitter.ParticleColor {
        let accent = palette.glow(for: hearthState(state))
        // Two hot colours rather than one, sampled per particle: a plume where
        // every ember is the identical shade reads as a texture, not as fire.
        let hot = color(brighten(accent, by: 1.35))
        let warm = color(accent)
        let cooled = color(Self.cooledEmber)
        return .evolving(start: .random(a: hot, b: warm), end: .single(cooled))
    }

    /// What an ember looks like just before it goes out. Not black: an ember
    /// that fades to black fades through grey, and grey has no business in a
    /// fire.
    private static let cooledEmber = SIMD3<Float>(0.62, 0.11, 0.03)

    private func brighten(_ c: SIMD3<Float>, by factor: Float) -> SIMD3<Float> {
        simd_min(c * factor, SIMD3<Float>(repeating: 1))
    }

    /// The rig speaks in `PersonaState` and the palette in `HearthState`. Same
    /// four beats, different names; this is the only place here that knows both.
    private func hearthState(_ state: PersonaState) -> HearthState {
        switch state {
        case .listening: return .LISTENING
        case .thinking:  return .THINKING
        case .speaking:  return .SPEAKING
        case .resting:   return .IDLE
        }
    }

    // MARK: - Scale

    /// How much smaller or larger this flame is than the one the numbers above
    /// were judged against.
    ///
    /// Everything the emitter takes -- speed, size, acceleration, noise -- is in
    /// metres or metres per second, and none of it means anything without a
    /// reference. Rather than restate each number as a fraction inline, the
    /// whole configuration is written for a reference flame and then scaled
    /// once. Which makes a single question answerable on device: if the embers
    /// are wrong at every size, the numbers are wrong; if they are right at one
    /// size and wrong at others, this factor is.
    private static func sizeFactor(_ world: ParticleWorld) -> Float {
        max(world.coreRadius, 0.0001) / referenceRadius
    }

    /// Sulivan's flame at full volumetric size: `sphereRadius * 1.05`.
    private static let referenceRadius: Float = 0.252

    // MARK: - Helpers

    private func color(_ c: SIMD3<Float>, alpha: Float = 1) -> UIColor {
        UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: CGFloat(alpha))
    }
}
