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
//  STATUS: all four turns are drawn, plus the pinch-and-hold crossing. Idle is
//  the BASE configuration and every other mood is written as what it changes
//  about the fire, which is the thing worth being able to read at a glance.
//  See section 15 of `tasks/vision-phase-4-5.md`.
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
        // rewrite the component. Clearing the applied mood is how, and it costs
        // one configuration write rather than a special path.
        mood = nil
    }

    public func reshape(to newWorld: ParticleWorld) {
        guard newWorld != world else { return }
        world = newWorld
        placeEmitter()
        mood = nil
    }

    // MARK: - The per-frame split, and why there is one

    /// Two kinds of lever, and keeping them apart is what makes the other three
    /// states affordable.
    ///
    /// CONFIGURATION -- birth rate, lifespan, colour, vortex, attraction -- is
    /// the emitter's rulebook, and rewriting it means writing back the whole
    /// value-type component. That happens on EDGES only: when the turn changes,
    /// when the palette changes, when the surface's budget changes.
    ///
    /// CONTINUOUS -- the mic level breathing the plume, the two-second hold
    /// drawing it in -- lives on the emitter entity's own TRANSFORM instead.
    /// Because `particlesInheritTransform` is true, scaling that entity moves
    /// the whole live plume, every frame, for the price of a transform write.
    ///
    /// That split is what keeps the rule from section 12 intact. Nothing here
    /// repositions an individual ember; the simulation stays authoritative and
    /// the whole system is moved around it.
    public func update(_ frame: ParticleFrame) {
        let wanted = wantedMood(for: frame)

        // 1. The rulebook, on edges.
        if wanted != mood || frame.density != appliedDensity {
            let firstEntry = wanted != mood
            mood = wanted
            appliedDensity = frame.density
            configure(wanted, density: frame.density, exhaling: firstEntry && wanted == .exhale)
        }

        // 2. The transform, every frame.
        applyPlumeScale(wanted, frame: frame)

        // 3. Syllables, while talking.
        if wanted == .speaking { detectOnset(frame) } else { lastLevel = frame.level }
    }

    /// What the fire should be doing this frame.
    ///
    /// The crossing OVERRIDES the turn, exactly as the flourish does for the
    /// fireflies: the hold is the same event whatever it interrupted, and a
    /// persona that kept gusting through it would be two things at once.
    private func wantedMood(for frame: ParticleFrame) -> Mood {
        guard frame.transition > 0.01 else {
            switch frame.state {
            case .resting:   return .resting
            case .listening: return .listening
            case .thinking:  return .thinking
            case .speaking:  return .speaking
            }
        }
        return frame.transition >= Self.exhaleAt ? .exhale : .crossing
    }

    private enum Mood: Equatable {
        case resting, listening, thinking, speaking, crossing, exhale
    }
    private var mood: Mood?
    private var appliedDensity: Float = -1

    // MARK: - The continuous lever

    /// The plume's overall size, eased toward whatever the current mood wants.
    ///
    /// Eased rather than set, because two of the three things that move it are
    /// interruptible. A hold abandoned at 1.4 seconds has to RELAX rather than
    /// snap, and easing gives that for free: the target simply goes back to one
    /// and the plume opens again on its own. No unwind path, which is where
    /// these usually break.
    private func applyPlumeScale(_ mood: Mood, frame: ParticleFrame) {
        switch mood {
        case .exhale:
            // SNAPPED, not eased, and this is the one place that is right.
            // The exhale has about sixty milliseconds before the window closes
            // -- easing would still be halfway through the collapse when the
            // scene changed, which would show as the burst never leaving.
            plumeScale = Self.exhaleScale
        case .crossing:
            plumeScale = ease(toward: 1 - (1 - Self.collapsedScale) * eased(frame.transition),
                              dt: frame.dt)
        case .listening:
            // The mic, breathing the whole field. The fireflies widen their
            // swirl for this; the fire swells instead, which is the same
            // sentence in the other language.
            plumeScale = ease(toward: 1 + Self.listenSwell * frame.level, dt: frame.dt)
        default:
            plumeScale = ease(toward: 1, dt: frame.dt)
        }
        emitter.scale = SIMD3<Float>(repeating: max(plumeScale, 0.02))
    }

    private func ease(toward target: Float, dt: Float) -> Float {
        plumeScale + (target - plumeScale) * min(1, dt * Self.plumeResponse)
    }

    /// Slow in, slow out, so the collapse does not read as linear machinery.
    private func eased(_ t: Float) -> Float {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }

    private var plumeScale: Float = 1

    /// How far in the plume is drawn by the end of a completed hold.
    private static let collapsedScale: Float = 0.30
    /// And how far out it is thrown the instant it lets go. Over one, so the
    /// transform contributes to the burst rather than fighting it: the shell
    /// the embers are born on expands at the same moment they are flung off it.
    private static let exhaleScale: Float = 1.15
    /// Where in the two seconds the collapse becomes the burst. Late, because
    /// the collapse IS the progress bar -- it has to be legible almost to the
    /// end for the hold to feel like it completed rather than like it was
    /// submitted.
    private static let exhaleAt: Float = 0.97
    /// How much the mic swells the plume at full level.
    private static let listenSwell: Float = 0.55
    /// Per second. Fast enough to track a voice, slow enough that the plume
    /// has weight.
    private static let plumeResponse: Float = 7.5

    // MARK: - Syllables

    /// One gust per syllable, and the fire is the only thing that has to notice.
    ///
    /// A RISE through a floor, not a level above it. Amplitude alone would
    /// burst continuously through a loud word and never during a quiet one; the
    /// onset -- the moment the level jumps -- is what a syllable actually is,
    /// and it is the same edge the flame mesh already pulses on. That is why
    /// this reads as matched rather than as two effects that happen to be busy
    /// at the same time.
    ///
    /// The refractory period is the whole safety margin. Speech runs at four to
    /// seven syllables a second; without a floor under the interval a noisy
    /// level would fire every frame and the gust would become a stream, which
    /// is precisely the state this is trying not to be.
    private func detectOnset(_ frame: ParticleFrame) {
        burstCooldown -= frame.dt
        let rising = frame.level - lastLevel
        lastLevel = frame.level
        guard burstCooldown <= 0,
              frame.level > Self.onsetFloor,
              rising > Self.onsetRise else { return }
        burstCooldown = Self.onsetRefractory
        component.burst()
        emitter.components.set(component)
    }

    private var lastLevel: Float = 0
    private var burstCooldown: Float = 0

    /// Below this the level is room noise, not a voice.
    private static let onsetFloor: Float = 0.10
    /// How much the level has to climb in one frame to count as an attack.
    private static let onsetRise: Float = 0.030
    /// Seconds. Nine gusts a second is already above the fastest speech.
    private static let onsetRefractory: Float = 0.11

    // MARK: - The configurations

    /// Write the emitter's rulebook for a mood.
    ///
    /// ONE base configuration with five departures from it, rather than six
    /// functions that are ninety percent the same. Idle IS the base -- the fire
    /// at rest -- and every other state is expressed as what it changes about
    /// the fire, which is the thing worth being able to read at a glance.
    private func configure(_ mood: Mood, density: Float, exhaling: Bool) {
        let scale = Self.sizeFactor(world)
        var component = baseComponent(density: density)
        var main = component.mainEmitter

        switch mood {
        case .resting:
            break

        case .listening:
            // THE FIRE DRAWS BREATH. Attraction toward the emitter's own origin
            // -- which is the eyes -- with the buoyancy almost switched off, so
            // embers still leave the skin and are then hauled back rather than
            // escaping. What that looks like is a fire when a door opens and
            // the air starts moving toward it: the plume gathers and hangs
            // instead of rising. Taking something in, in fire's own words.
            main.attractionCenter = .zero
            main.attractionStrength = 0.9
            main.acceleration = SIMD3<Float>(0, 0.015 * scale, 0)
            main.dampingFactor = 0.62
            main.lifeSpan = 3.0
            main.lifeSpanVariation = 1.0
            main.birthRate = 30 * density
            main.spreadingAngle = 0.60
            // Quieter turbulence, because a held breath should look held. Noise
            // at idle strength would read as fidgeting.
            main.noiseStrength = 0.085 * scale
            component.speed = 0.060 * scale

        case .thinking:
            // A FIRE WHIRL. Vertical axis, which is the choice that keeps this
            // fire rather than making it a diagram: the alternative -- spinning
            // about the viewer's axis, the way the fireflies stand their ring
            // up to frame the face -- fights buoyancy the whole way and stops
            // looking like anything that burns. The flame already frames the
            // face here, which the bead never did.
            main.vortexStrength = 1.4
            main.vortexDirection = SIMD3<Float>(0, 1, 0)
            // STREAKS, not dots. A spiral drawn by points is a scatter; drawn
            // by short traces along the path, it is a spiral. This is the one
            // number doing most of the work in this state.
            main.stretchFactor = 1.5
            main.lifeSpan = 3.2
            main.lifeSpanVariation = 0.9
            main.birthRate = 34 * density
            // Less lift, so the whirl stays a whirl. Full buoyancy stretches it
            // into a helix so tall that the turning is no longer visible.
            main.acceleration = SIMD3<Float>(0, 0.045 * scale, 0)
            // And barely any damping, because the tangential speed IS the
            // effect. Damping is what kills a vortex.
            main.dampingFactor = 0.22
            main.spreadingAngle = 0.50
            main.noiseStrength = 0.070 * scale

        case .speaking:
            // GUSTS. The continuous configuration is only the bed the bursts
            // land on -- see `detectOnset`, which is where this state actually
            // happens.
            main.birthRate = 40 * density
            main.spreadingAngle = 1.05
            main.lifeSpan = 2.0
            main.lifeSpanVariation = 0.8
            main.dampingFactor = 0.30
            // A drift toward whoever is being spoken to. The face card sits at
            // +z, so +z is out of the front of him: the embers travel at the
            // listener rather than merely upward, which is a small thing that
            // makes the fire feel aimed.
            main.acceleration = SIMD3<Float>(0, 0.055 * scale, 0.030 * scale)
            component.speed = 0.100 * scale
            component.speedVariation = 0.080 * scale
            component.burstCount = 14
            component.burstCountVariation = 6

        case .crossing:
            // THE COLLAPSE, and it is the progress bar. Hard attraction, no
            // buoyancy at all, heavy damping and a short life: the fire hauls
            // its embers in and goes tight and quiet, and how tight it has got
            // is how far through the two seconds you are. Nothing has to be
            // drawn to say the hold is building.
            //
            // The transform is doing the other half of this -- see
            // `applyPlumeScale`. Attraction alone gathers them; the scale ramp
            // is what makes the gathering read as continuous rather than as the
            // plume simply getting denser.
            main.attractionCenter = .zero
            main.attractionStrength = 3.2
            main.acceleration = .zero
            main.dampingFactor = 0.85
            main.lifeSpan = 1.6
            main.lifeSpanVariation = 0.4
            main.birthRate = 55 * density
            main.spreadingAngle = 0.25
            main.noiseStrength = 0.030 * scale
            component.speed = 0.045 * scale
            component.speedVariation = 0.025 * scale
            // Held hot. A ramp that cools on the way in would make the collapse
            // look like the fire going out, which is the opposite of what a
            // crossing means.
            main.colorEvolutionPower = 3.0

        case .exhale:
            // ONE BURST, and then the window closes over it.
            //
            // Birth rate goes to ZERO deliberately: the burst IS the event, and
            // a continuous stream underneath it would blur the single moment
            // this whole two seconds was building toward into just more fire.
            //
            // High damping with no acceleration makes it a shockwave rather
            // than a fountain -- the embers fling out, stop, and fade where
            // they stopped. A fountain would still be climbing when the scene
            // changed, and a flourish half-finished at the cut is worse than
            // none.
            main.birthRate = 0
            main.attractionStrength = 0
            main.acceleration = .zero
            main.dampingFactor = 0.90
            main.lifeSpan = 1.1
            main.lifeSpanVariation = 0.4
            main.spreadingAngle = .pi
            main.sizeMultiplierAtEndOfLifespan = 0.05
            main.stretchFactor = 1.2
            component.speed = 0.55 * scale
            component.speedVariation = 0.25 * scale
            component.burstCount = 90
            component.burstCountVariation = 20
        }

        main.color = emberColor(for: mood)
        component.mainEmitter = main
        // Fired from inside the configuration so the burst is spawned under the
        // rules it belongs to. Calling it afterwards would spend the crossing's
        // narrow cone on the one moment that wants everything.
        if exhaling { component.burst() }
        // Value type: the component has to be set back, not merely mutated.
        self.component = component
        emitter.components.set(component)
    }

    /// The component the caller currently has on the emitter. Kept so a gust
    /// can be fired without rebuilding the rulebook around it.
    private var component = ParticleEmitterComponent()

    /// Idle: a slow, sparse rise. The fire is burning and nobody is talking to
    /// it -- and it is also the baseline every other state is written against.
    ///
    /// The numbers are chosen against a flame roughly 25cm wide and 80cm tall
    /// -- Sulivan at his full volumetric size -- and every one of them is scaled
    /// by `sizeFactor`, so a Sulivan pinched down to a desk toy gets embers in
    /// proportion instead of a shower of boulders.
    private func baseComponent(density: Float) -> ParticleEmitterComponent {
        let scale = Self.sizeFactor(world)
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
        // embers start too far out, this factor of two is the first suspect and
        // halving it is the whole fix.
        component.emitterShapeSize = SIMD3<Float>(
            repeating: world.waistRadius * 2 * Self.birthSpread)
        component.birthLocation = .surface
        component.birthDirection = .normal

        // Slow, but not as slow as the first pass. An ember's speed comes from
        // the air around it, not from a launch, and anything much faster reads
        // as sparks off a grinder -- but too slow and buoyancy wins immediately,
        // which is what kept the plume as narrow as the flame. The outward
        // travel has to survive long enough to get clear.
        component.speed = 0.085 * scale
        component.speedVariation = 0.070 * scale

        // PARTICLES FOLLOW THE PERSONA. The alternative -- leaving embers
        // behind in world space as Sulivan is carried across a room -- is more
        // physical and genuinely lovely, and it is the wrong trade for the
        // first pass: it also means the plume does not scale when he is pinched
        // down to a tennis ball, and a fire whose embers are the wrong size
        // reads as broken in a way a fire that does not trail does not.
        //
        // It has since earned its keep twice over, because it is what makes the
        // emitter's TRANSFORM a usable lever at all -- the mic swell and the
        // hold's collapse both ride on it.
        component.particlesInheritTransform = true
        component.simulationState = .play
        component.isEmitting = true

        var main = component.mainEmitter

        // Sparse. Fewer, better-seen embers beat a haze -- the same lesson the
        // firefly twinkle taught, where a hundred dots at a tenth opacity read
        // as clutter and a third of them at full opacity read as fireflies.
        main.birthRate = 26 * density
        main.birthRateVariation = 10 * density

        // Long enough to travel a flame-height and a bit past it. Embers that
        // die at the crown look like the flame has a lid.
        main.lifeSpan = 2.4
        main.lifeSpanVariation = 1.1

        main.size = 0.0075 * scale
        main.sizeVariation = 0.004 * scale
        // Embers SHRINK as they burn out. Fading alone leaves ghosts of the
        // original size hanging in the air.
        main.sizeMultiplierAtEndOfLifespan = 0.15

        // BUOYANCY, which is the whole reason a `.normal` birth direction works
        // here. Embers leave the flame in every direction and are then all bent
        // upward by the same rising column of air. Damping is what makes that
        // bend look like air rather than gravity: they lose their initial
        // speed, and what remains is the lift.
        main.acceleration = SIMD3<Float>(0, 0.062 * scale, 0)
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
        main.noiseStrength = 0.125 * scale
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

        // Above 1 the ember holds its hot colour for most of its life and cools
        // late, which is how a real one behaves: the colour change is the last
        // thing that happens before it goes out.
        main.colorEvolutionPower = 1.6

        component.mainEmitter = main
        return component
    }
    // MARK: - Colour

    /// The ember's hot-to-cold ramp for a turn.
    ///
    /// The HOT end is the persona's own accent for the state, which is what
    /// ties the fire to whoever is wearing it and makes the turn readable from
    /// across a room: the embers warm toward the speaking accent and cool
    /// toward the thinking one, without a single extra wire. The COLD end is
    /// fixed, because a dying ember is the same deep red whatever was burning.
    private func emberColor(for mood: Mood)
    -> ParticleEmitterComponent.ParticleEmitter.ParticleColor {
        let accent = palette.glow(for: hearthState(mood))
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
    ///
    /// The two crossing moods borrow the SPEAKING accent, which is the warmest
    /// one a persona carries. A crossing is not a turn and has no colour of its
    /// own, and the alternative -- holding whatever the turn happened to be --
    /// would mean the same flourish came out cold when it interrupted a
    /// thinking beat. The flourish should look the same every time it happens.
    private func hearthState(_ mood: Mood) -> HearthState {
        switch mood {
        case .listening: return .LISTENING
        case .thinking:  return .THINKING
        case .speaking, .crossing, .exhale: return .SPEAKING
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
