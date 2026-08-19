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
//  restarts nothing but is not free. So the rulebook is EDGE-TRIGGERED -- it is
//  written when the mood changes, not every frame -- and the two things that
//  genuinely have to move continuously, the mic swell and the hold's collapse,
//  ride the emitter entity's TRANSFORM instead. See `update(_:)`.
//
//  TWO EMITTERS, NOT ONE. The body plume sits at the persona's eyes and burns
//  through every mood. The crown sits near the flame's tip, carries no
//  continuous output whatsoever, and exists to be burst once per syllable. They
//  are separate because a burst needs a shared ORIGIN as much as a shared
//  direction, and because a fire that stops being a fire while it talks is not
//  a fire that is talking.
//
//  STATUS: all four turns are drawn, plus the pinch-and-hold crossing. Idle is
//  the BASE configuration and every other mood is written as what it changes
//  about the fire, which is the thing worth being able to read at a glance.
//  See sections 15 and 16 of `tasks/vision-phase-4-5.md`.
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

    /// A SECOND emitter, at the flame's tip, that only ever bursts.
    ///
    /// WHY A SECOND ONE. Speaking was configured on the body emitter, and the
    /// body emitter is a sphere as wide as the flame with particles born on its
    /// SURFACE. Every spark therefore left from a different point on a
    /// half-metre ball -- and even with all of them aimed up, a burst whose
    /// sources are spread across the whole silhouette does not read as a burst.
    /// It is the shared ORIGIN as much as the shared direction that makes one.
    ///
    /// It also lets the fire keep burning while it talks, which one emitter
    /// could not: reconfiguring the body into a spark jet meant the plume
    /// stopped being a plume for the length of every sentence. Now the body
    /// stays a fire, mildly agitated, and the crown erupts.
    ///
    /// It carries no continuous stream at all -- birth rate is zero, always --
    /// so it needs no state machine. It sits there emitting nothing, and a
    /// syllable bursts it.
    private let crown = Entity()

    private var core: ParticleCore
    private var palette: PersonaPalette

    /// The configuration currently written into the component. Nil forces the
    /// next update to write one.
    private var appliedState: PersonaState?

    public init(core: ParticleCore, palette: PersonaPalette) {
        self.core = core
        self.palette = palette
        root.name = "EmberField"
        emitter.name = "EmberEmitter"
        crown.name = "EmberCrown"
        root.addChild(emitter)
        root.addChild(crown)
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
        emitter.position = SIMD3<Float>(0, core.eyeHeight, 0)
        // The crown sits INSIDE the taper rather than on top of it. At the
        // visible top exactly, sparks appear to detach from a point floating
        // above the flame; a little under, they erupt out of it.
        crown.position = SIMD3<Float>(0, core.coreHeight * Self.crownHeight, 0)
    }

    /// How far up the flame the spark jet sits, as a fraction of its visible
    /// top.
    private static let crownHeight: Float = 0.80
    /// How much of the flame's height the birth column spans, against its
    /// visible top. Slightly over one, because the flame hangs below the rig's
    /// origin as well as standing above it.
    private static let birthColumn: Float = 1.15
    /// How wide the jet's mouth is, against the flame's waist. Small, because
    /// the flame has nearly closed up by this height and a wide mouth would put
    /// sparks outside a silhouette that has already tapered away.
    private static let crownSpread: Float = 0.30

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

    public func reshape(to newWorld: ParticleCore) {
        guard newWorld != core else { return }
        core = newWorld
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
        sparks.burst()
        crown.components.set(sparks)
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
        var component = baseComponent(density: density)
        var main = component.mainEmitter

        switch mood {
        case .resting:
            break

        case .listening:
            // THE FIRE DRAWS UPWARD. A gentle spiral that RISES.
            //
            // This replaces a gather-and-hang built on attraction, and the
            // rewrite is for two reasons. The first is that it was wrong: the
            // attraction was resolving against the world origin (see
            // `fieldSimulationSpace` above), so what it actually did was pull
            // the embers at the person. The second is that even fixed it would
            // have been the wrong idea -- on device it read as idle with the
            // life taken out of it, because a plume that stops rising loses the
            // one thing that made it look like fire, and a state that reads as
            // "less" is not a state.
            //
            // Rising is the better answer anyway. Attention is upward: a fire
            // being listened to draws, the way a chimney draws.
            main.vortexStrength = 0.55
            main.vortexDirection = SIMD3<Float>(0, 1, 0)
            // Lift well above idle -- this is the state's whole character.
            main.acceleration = SIMD3<Float>(0, 0.400, 0)
            main.dampingFactor = 0.12
            // Long, so the spiral has room to draw itself tall.
            main.lifeSpan = 3.4
            main.lifeSpanVariation = 1.0
            main.birthRate = 60 * density
            // NARROWER than idle, which is what separates the two at a glance:
            // idle is a wide slow cloud, listening is a column going somewhere.
            main.spreadingAngle = 0.30
            // Enough trace to see the curl. Below thinking, which is all streak.
            main.stretchFactor = 1.20
            // Quiet turbulence so the spiral stays a spiral. Noise at idle
            // strength scribbles over the shape the vortex is drawing.
            main.noiseStrength = 0.050
            // Low outward speed: the LIFT is doing the work here, not the birth
            // velocity. Sideways speed at idle levels would flatten the column
            // back into the cloud it is trying not to be.
            component.speed = 0.025

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
            main.stretchFactor = 1.80
            main.lifeSpan = 3.2
            main.lifeSpanVariation = 0.9
            main.birthRate = 62 * density
            // Less lift, so the whirl stays a whirl. Full buoyancy stretches it
            // into a helix so tall that the turning is no longer visible.
            main.acceleration = SIMD3<Float>(0, 0.100, 0)
            // And barely any damping, because the tangential speed IS the
            // effect. Damping is what kills a vortex.
            main.dampingFactor = 0.10
            main.spreadingAngle = 0.45
            main.noiseStrength = 0.060

        case .speaking:
            // THE FIRE IS AGITATED, and that is all this case does. The event
            // itself happens at the crown -- see `sparkComponent`.
            //
            // The first pass turned the BODY into the spark jet, which is what
            // made the sparks come from everywhere: the body is a sphere as
            // wide as the flame with particles born on its surface. Aiming them
            // all upward was not enough, because a burst needs a shared origin
            // as much as a shared direction.
            //
            // So the body keeps doing what a fire does and merely does it
            // harder: a little more lift, a little more turbulence, a slightly
            // wider mouth. Under the sparks it reads as the fire working.
            main.birthRate = 64 * density
            main.acceleration = SIMD3<Float>(0, 0.340, 0)
            main.lifeSpan = 2.0
            main.lifeSpanVariation = 0.8
            main.spreadingAngle = 0.65
            main.noiseStrength = 0.140
            component.speed = 0.050

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
            main.birthRate = 90 * density
            main.spreadingAngle = 0.25
            main.noiseStrength = 0.030
            component.speed = 0.040
            component.speedVariation = 0.025
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
            component.speed = 0.550
            component.speedVariation = 0.250
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

        // The crown is rewritten alongside the body rather than on its own
        // schedule. It depends on exactly the same three things -- the palette,
        // the flame's geometry, the surface's budget -- and every one of them
        // already arrives here as a cleared mood, so a second edge to track
        // would only be a second edge to get wrong.
        sparks = sparkComponent(density: density)
        crown.components.set(sparks)
    }

    /// The spark jet. Apple's own `sparks` preset, then argued with.
    ///
    /// STARTING FROM THE PRESET rather than from a bare component is worth it
    /// for one thing above all: whatever texture and streak character Apple
    /// shipped with it is tuned, and this project has no reason to re-derive
    /// it. Everything that makes a spark THIS fire's spark is overridden below.
    private func sparkComponent(density: Float) -> ParticleEmitterComponent {
        var component = ParticleEmitterComponent.Presets.sparks

        // TIMING, STATED, and this is the likeliest reason the first pass drew
        // nothing whatsoever.
        //
        // A preset called `sparks` is an IMPACT effect, and an impact effect is
        // `.once` -- it emits for a moment when it is installed and is then
        // finished forever. Inheriting that meant this emitter was already dead
        // before anybody spoke, and no amount of `burst()` revives an emitter
        // whose timing has run out.
        //
        // The lesson generalises past the bug: a preset is a bundle of
        // decisions, and the ones it makes about LIFECYCLE are exactly the ones
        // that never show up as a wrong-looking particle. They show up as
        // nothing at all, which is the hardest thing to read off a recording.
        component.timing = .repeating(emit: .init(duration: 86_400))

        // A small mouth at the flame's tip, born through the VOLUME rather than
        // on a surface: a surface birth on a shape this small puts every spark
        // on a ring, and a ring is visible as a ring.
        component.emitterShape = .sphere
        component.emitterShapeSize = SIMD3<Float>(
            repeating: core.waistRadius * 2 * Self.crownSpread)
        component.birthLocation = .volume
        // Local up, so a Sulivan who has been turned throws sparks out of HIS
        // top rather than the room's. See the rule in ParticleField.swift.
        component.birthDirection = .local
        component.emissionDirection = SIMD3<Float>(0, 1, 0)
        component.fieldSimulationSpace = .local
        component.particlesInheritTransform = true
        component.simulationState = .play
        component.isEmitting = true
        component.speed = 0.420
        component.speedVariation = 0.220
        // What a syllable is worth, budgeted like everything else that
        // multiplies.
        component.burstCount = Int(22 * density)
        component.burstCountVariation = Int(8 * density)

        var main = component.mainEmitter
        // A THIN TRICKLE rather than nothing, and it is not the bed that hid
        // the bursts before -- that was forty a second on the BODY, competing
        // with the sparks at the same size and colour. Five a second from the
        // tip is a fire that occasionally spits while it talks.
        //
        // It is worth more than the purity of a zero, because it makes the
        // emitter's own liveness VISIBLE. The last recording could not
        // distinguish "the bursts are not firing" from "the emitter is not
        // alive", and those two want completely different fixes.
        main.birthRate = 5 * density
        main.birthRateVariation = 3 * density
        main.spreadingAngle = 0.42

        // A SHORT LIFE, which is the whole difference between a spark and an
        // ember. The embers underneath live two and a half seconds and drift;
        // these live half of one and are gone. Two populations with visibly
        // different clocks read as two things, which is what lets the syllables
        // stay legible on top of a fire that is already moving.
        main.lifeSpan = 0.55
        main.lifeSpanVariation = 0.25

        main.size = 0.0055
        main.sizeVariation = 0.0025
        main.sizeMultiplierAtEndOfLifespan = 0.02

        // DOWNWARD, and it is not a typo. Embers are lighter than the air they
        // are in and rise; a spark is a thrown fragment and arcs. Giving the two
        // populations opposite signs on the same axis is most of what stops the
        // sparks from being read as simply more embers.
        main.acceleration = SIMD3<Float>(0, -0.050, 0)
        main.dampingFactor = 0.30

        // Long streaks. A spark is seen as a line, and at this speed a dot
        // would read as a dot -- the third time this phase that has been the
        // answer.
        main.stretchFactor = 2.2
        // Almost no wander: sparks fly straight, and turbulence would scatter a
        // burst back into the cloud it is trying to stand out from.
        main.noiseStrength = 0.020

        main.opacityCurve = .easeFadeOut
        main.blendMode = .additive
        main.sortOrder = .unsorted
        main.isLightingEnabled = false
        // Always the speaking accent, because that is the only turn this
        // emitter ever fires in.
        main.color = emberColor(for: .speaking)
        main.colorEvolutionPower = 1.2

        component.mainEmitter = main
        return component
    }

    /// The crown's component, kept so a syllable can burst it without
    /// rebuilding it.
    private var sparks = ParticleEmitterComponent()

    /// The component the caller currently has on the emitter. Kept so a gust
    /// can be fired without rebuilding the rulebook around it.
    private var component = ParticleEmitterComponent()

    /// Idle: a slow, sparse rise. The fire is burning and nobody is talking to
    /// it -- and it is also the baseline every other state is written against.
    ///
    /// The numbers are in the RIG'S units, where the flame is 25cm across and
    /// 78cm tall whatever size the persona is actually being shown at. The
    /// hierarchy converts them -- see the note on scale below.
    private func baseComponent(density: Float) -> ParticleEmitterComponent {
        var component = ParticleEmitterComponent()

        // A COLUMN THROUGH THE FLAME, and this replaces a shell around it.
        //
        // The first pass was a sphere with particles born on its SURFACE and
        // leaving along the surface NORMAL. Both halves were wrong, and the
        // recording showed exactly how: a sphere has a bottom, so a third of
        // every ember was born UNDER the fire and pushed downward, and what was
        // left was a ball of dots distributed evenly around the flame rather
        // than anything rising off it. Embers do not come out of the bottom of
        // a fire.
        //
        // A cylinder spanning the flame's body, born through its VOLUME, is the
        // honest shape: a flame is a column of hot gas and an ember can be
        // lifted from anywhere inside it. Volume rather than surface also
        // removes the shell artefact -- a surface birth puts every particle on
        // a thin skin, and a skin is visible as a skin.
        component.emitterShape = .cylinder
        component.emitterShapeSize = SIMD3<Float>(
            core.waistRadius * 2 * Self.birthSpread,
            core.coreHeight * Self.birthColumn,
            core.waistRadius * 2 * Self.birthSpread)
        component.birthLocation = .volume
        // AND THEY ALL LEAVE UPWARD. `.normal` was the other half of the ball:
        // it aimed each ember along whichever way its birth point happened to
        // face, which averages to nothing. Local up, so a persona who has been
        // turned still sends embers out of his own top rather than the room's.
        component.birthDirection = .local
        component.emissionDirection = SIMD3<Float>(0, 1, 0)

        // SLOW OUT, FAST UP, and the ratio is the whole fix.
        //
        // It used to be the other way round. Outward travel settled around
        // speed-over-damping, roughly a quarter metre; the buoyant rise over a
        // 2.4 second life was about two thirds of that. Sideways beat up, so
        // the result was a ball however the noise was tuned. Now the birth
        // velocity is small and the LIFT does the work -- which is also what
        // actually happens to an ember.
        component.speed = 0.035
        component.speedVariation = 0.030

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
        // FORCE FIELDS ARE LOCAL TO THE EMITTER, and this is a bug fix rather
        // than a preference.
        //
        // `attractionCenter` and `vortexDirection` are both points and axes in
        // whatever space this names. Left unstated, the listening attraction
        // toward `.zero` was pulling embers at the WORLD origin -- which in an
        // immersive session is roughly where the person was standing when the
        // space opened. On device that read exactly as reported: the embers
        // flowing toward the viewer, for no reason anything in this file could
        // explain.
        //
        // The vortex had the same latent fault waiting: an axis through the
        // world origin rather than through the fire, which would have spun
        // Sulivan's embers around a point somewhere across the room.
        component.fieldSimulationSpace = .local
        component.simulationState = .play
        component.isEmitting = true

        var main = component.mainEmitter

        // Sparse. Fewer, better-seen embers beat a haze -- the same lesson the
        // firefly twinkle taught, where a hundred dots at a tenth opacity read
        // as clutter and a third of them at full opacity read as fireflies.
        // DENSER. On device the field read as a dozen specks. At 26 a second
        // over a 2.4 second life the steady state is about sixty embers -- but
        // most of those sixty are INSIDE the flame, where an additive dot on a
        // bright gold surface is invisible. Only the escapees are ever seen, so
        // the rate has to be set for them rather than for the population.
        main.birthRate = 55 * density
        main.birthRateVariation = 18 * density

        // Long enough to travel a flame-height and a bit past it. Embers that
        // die at the crown look like the flame has a lid.
        main.lifeSpan = 2.4
        main.lifeSpanVariation = 1.1

        main.size = 0.0090
        main.sizeVariation = 0.0040
        // Embers SHRINK as they burn out. Fading alone leaves ghosts of the
        // original size hanging in the air.
        main.sizeMultiplierAtEndOfLifespan = 0.15

        // BUOYANCY, now the dominant force rather than a bias on top of one.
        // Four times what it was: over a 2.4 second life this carries an ember
        // most of a metre, comfortably past the flame's crown. An ember that
        // dies before it clears the fire may as well not have been born,
        // because nothing inside the flame can be seen against it.
        main.acceleration = SIMD3<Float>(0, 0.260, 0)
        // Damping down again, to stop fighting the rise. Drag is what caps the
        // climb, and the climb is the effect.
        main.dampingFactor = 0.15
        // A narrower cone than the shell needed. With every ember already
        // leaving upward, the spread is the plume's TAPER rather than its
        // shape -- and a wide one only puts embers back out to the sides.
        main.spreadingAngle = 0.55

        // The wander. A fire's air is turbulent, and embers that rise in
        // straight lines look like a fountain. Kept low: strong noise turns a
        // plume into a snowstorm.
        main.noiseStrength = 0.100
        // Scale DOWN as strength goes up: a lower number is a larger swirl, and
        // large slow swirls are what carry a plume sideways. Small strong ones
        // just make every ember jitter in place.
        main.noiseScale = 1.15
        main.noiseAnimationSpeed = 0.24

        main.opacityCurve = .easeFadeOut
        // STREAKS, and 0.35 was not one. On device every ember was a round dot:
        // a moving thing drawn as a point reads as a point, which is the same
        // lesson the thinking whirl and the first spark pass each taught.
        // Three times the number, and still under the sparks'.
        main.stretchFactor = 1.10

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

    // MARK: - Scale, and the multiply that did nothing

    // THERE IS NO SIZE FACTOR ANY MORE, and removing it is a correction rather
    // than a simplification.
    //
    // Every number in this file used to be multiplied by
    // `coreRadius / 0.252`, written to answer the open question of whether
    // emitter output scales with entity scale. It was always exactly 1.0.
    // `coreRadius` is `flameMesh.radius`, which is `sphereRadius * 1.05` -- a
    // constant of the rig's LOCAL space, which does not change when a persona
    // is pinched from a tennis ball to life size. The size lives in
    // `rootEntity.scale`, several nodes up.
    //
    // Nothing was broken by it, because the answer to the original question
    // turns out to be that the hierarchy already does the scaling: the emitter
    // is a descendant of the rig root, `particlesInheritTransform` is true, and
    // every metre written here is a rig-local metre that the transform converts
    // on the way out. What the factor actually did was cost a multiply per
    // number and offer false reassurance -- the device test it was built for
    // ("wrong at every size means the numbers, wrong at some sizes means the
    // factor") could never have distinguished anything.
    //
    // So: every number here is in the RIG'S units, where the flame is 0.25
    // across and 0.78 tall. That is the reference, and it is a fact about the
    // geometry rather than a variable.

    // MARK: - Helpers

    private func color(_ c: SIMD3<Float>, alpha: Float = 1) -> UIColor {
        UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: CGFloat(alpha))
    }
}
