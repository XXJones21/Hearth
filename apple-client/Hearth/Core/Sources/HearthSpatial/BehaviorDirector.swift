//
//  BehaviorDirector.swift
//  HearthSpatial
//
//  Where the orb goes, and why.
//
//  The harness names a performance -- `consulting_journal`, `searching_files`,
//  `remembering` -- and this resolves that name against a table of primitives
//  and plays it. Adding a behaviour is a table entry. That is the whole design:
//  a new cue from a house that learned a new tool should cost nothing on the
//  client, and a cue nobody has ever seen should still do SOMETHING sensible.
//
//  DELIBERATELY NOT A SECOND STATE MACHINE. FaceDirector owns the face's timing
//  and PersonaRig owns the per-state choreography of the bead and its field;
//  this owns only the rig's POSITION and ORIENTATION in the scene. The three
//  never argue because they never overlap: a behaviour moves the orb, the rig
//  decides what the orb looks like while it moves, and the face decides what it
//  is doing with its eyes. An orb that flew to the shelf AND decided it was
//  thinking would be two answers to one question.
//
//  The primitives interpolate per frame rather than handing RealityKit an
//  animation with a completion. Same composability, and it keeps the whole
//  sequencer synchronous and inspectable -- the rig is already ticked once per
//  frame from the host's update loop, and a behaviour that advances on that
//  same tick cannot fall out of step with the thing it is moving.
//

import Foundation
import simd
import HearthCore

// MARK: - Primitives

/// One step of a performance. Positions are in the rig's parent space, the
/// same space the host places the rig in.
public enum BehaviorPrimitive: Sendable, Equatable {
    /// Travel to a named target over `seconds`. Unknown names resolve to home,
    /// so a behaviour referring to a shelf that does not exist yet drifts back
    /// rather than flying to the origin.
    case flyTo(target: String, seconds: Float)
    /// Hold near a named target, bobbing gently, for `seconds`.
    case hoverAt(target: String, seconds: Float, bob: Float)
    /// Sit still for `seconds`. The pause that makes a performance read as
    /// deliberate rather than mechanical.
    case dwell(seconds: Float)
    /// Travel back to where the orb lives.
    case returnHome(seconds: Float)
}

/// A named performance: what to do, and how it behaves when interrupted.
public struct Behavior: Sendable, Equatable {
    public let primitives: [BehaviorPrimitive]

    /// Replay the primitives until an `end` cue arrives rather than running
    /// once. Work that takes an unknown length of time -- which is most work --
    /// wants this, because a performance that finishes early leaves the orb
    /// sitting at home while the house is still busy.
    public let loops: Bool

    /// The orb keeps its position when speech begins.
    ///
    /// The default is false and that is the interesting case: when the house
    /// starts talking, the orb should come back toward the person it is talking
    /// TO. A behaviour that sets this is one where staying put is the point --
    /// reading aloud from an open book, say, where flying home mid-sentence
    /// would undo the whole picture.
    public let speakInPlace: Bool

    public init(primitives: [BehaviorPrimitive], loops: Bool = true, speakInPlace: Bool = false) {
        self.primitives = primitives
        self.loops = loops
        self.speakInPlace = speakInPlace
    }
}

// MARK: - Director

@MainActor
public final class BehaviorDirector {
    /// Named places the orb can be sent. The host registers these because only
    /// the host knows where it put the shelf.
    private var targets: [String: SIMD3<Float>] = [:]

    /// Where the orb lives when nothing is happening.
    public var home: SIMD3<Float> = .zero

    /// The behaviour table. Public so a host can extend or override it without
    /// this file having to know every tool a house might grow.
    public var library: [String: Behavior] = BehaviorDirector.defaultLibrary

    /// What the generic answer is. Every unknown cue lands here.
    public var fallbackBehavior: Behavior = BehaviorDirector.working

    private var running: Behavior?
    private var runningName: String?
    private var stepIndex = 0
    private var stepElapsed: Float = 0
    private var stepStart: SIMD3<Float> = .zero
    private var lastRevision: UInt64 = 0

    /// Current offset from home, eased. The rig's position is home + this.
    private var position: SIMD3<Float> = .zero
    private var bobPhase: Float = 0

    public init() {}

    /// Tell the director where something is. Passing nil forgets it.
    public func setTarget(_ name: String, at position: SIMD3<Float>?) {
        targets[name] = position
    }

    /// True while a performance is playing. The host can use this to decide
    /// whether the orb is available for anything else.
    public var isPerforming: Bool { running != nil }

    /// WHICH performance is playing, or nil. A host that stages props for
    /// particular behaviours -- the library the orb reads from while consulting
    /// a journal -- needs the name and not just the fact.
    public var performing: String? { runningName }

    /// Stop whatever is running and come back. The single exit, so every reason
    /// to abandon a performance -- an `end` cue, a new turn, an error, speech
    /// beginning under a behaviour that does not hold its ground -- leaves the
    /// orb in the same state.
    public func recall() {
        guard running != nil else { return }
        running = nil
        runningName = nil
        stepIndex = 0
        stepElapsed = 0
        stepStart = position
    }

    /// One frame.
    ///
    /// - Parameters:
    ///   - speaking: the house is talking. A behaviour without `speakInPlace`
    ///     yields to this, because the orb's first duty while speaking is to be
    ///     near the person it is speaking to.
    /// - Returns: the offset from home to apply to the rig this frame.
    ///
    /// No clock argument, deliberately. A cue's `at` timestamp is not what
    /// decides whether it has been seen -- `revision` is -- so the director
    /// needs no notion of the time, and taking one would only invite a second
    /// clock to drift against the face's.
    public func tick(dt: Float, speaking: Bool) -> SIMD3<Float> {
        consumeCue()

        if speaking, let running, !running.speakInPlace {
            recall()
        }

        bobPhase += dt

        guard let running else {
            // Nothing playing: ease back to home and stay there.
            position = approach(position, .zero, dt: dt, tau: 0.45)
            return position
        }

        guard stepIndex < running.primitives.count else {
            if running.loops {
                stepIndex = 0
                stepElapsed = 0
                stepStart = position
            } else {
                recall()
            }
            return position
        }

        let step = running.primitives[stepIndex]
        stepElapsed += dt

        switch step {
        case let .flyTo(target, seconds):
            let goal = resolve(target)
            position = ease(from: stepStart, to: goal, t: progress(stepElapsed, seconds))
            advanceIfDone(stepElapsed, seconds)

        case let .hoverAt(target, seconds, bob):
            let goal = resolve(target)
            // Settle onto the target quickly, then breathe there. The bob is
            // the whole tell that the orb is WAITING rather than parked.
            let settled = approach(position, goal, dt: dt, tau: 0.35)
            position = settled + SIMD3<Float>(0, sin(bobPhase * 1.6) * bob, 0)
            advanceIfDone(stepElapsed, seconds)

        case let .dwell(seconds):
            advanceIfDone(stepElapsed, seconds)

        case let .returnHome(seconds):
            position = ease(from: stepStart, to: .zero, t: progress(stepElapsed, seconds))
            advanceIfDone(stepElapsed, seconds)
        }

        return position
    }

    // MARK: - Cues

    private func consumeCue() {
        let feed = BehaviorFeed.shared
        guard feed.revision != lastRevision, let cue = feed.cue else { return }
        lastRevision = feed.revision

        switch cue.phase {
        case .start:
            // A start preempts whatever was playing, including itself: a second
            // `consulting_journal` is a second journal, and it should restart
            // the flight rather than be swallowed as a duplicate.
            let behavior = library[cue.name] ?? fallbackBehavior
            running = behavior
            runningName = cue.name
            stepIndex = 0
            stepElapsed = 0
            stepStart = position

        case .end:
            // Only the performance that is actually running. An `end` for
            // something that already yielded -- to speech, to a newer cue --
            // must not recall the orb from whatever replaced it.
            if runningName == cue.name { recall() }
        }
    }

    // MARK: - Geometry

    private func resolve(_ target: String) -> SIMD3<Float> {
        targets[target].map { $0 - home } ?? .zero
    }

    private func progress(_ elapsed: Float, _ seconds: Float) -> Float {
        seconds <= 0 ? 1 : min(1, elapsed / seconds)
    }

    private func advanceIfDone(_ elapsed: Float, _ seconds: Float) {
        guard elapsed >= seconds else { return }
        stepIndex += 1
        stepElapsed = 0
        stepStart = position
    }

    /// Smoothstepped interpolation. The orb accelerates out of rest and settles
    /// into arrival; a linear fly-to reads as a machine moving a prop.
    private func ease(from a: SIMD3<Float>, to b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        let s = t * t * (3 - 2 * t)
        return a + (b - a) * s
    }

    /// Frame-rate independent approach, for the steps that have no fixed
    /// duration to interpolate over.
    private func approach(_ a: SIMD3<Float>, _ b: SIMD3<Float>, dt: Float, tau: Float) -> SIMD3<Float> {
        let k = 1 - exp(-dt / max(tau, 1e-3))
        return a + (b - a) * k
    }
}

// MARK: - The library

public extension BehaviorDirector {
    /// The generic answer, and the one every unknown cue resolves to.
    ///
    /// Deliberately modest: a small lift and a hover, near home. It has to be
    /// legible for work nobody has named yet, which means it cannot look like
    /// anything specific.
    static let working = Behavior(primitives: [
        .flyTo(target: "workspace", seconds: 0.7),
        .hoverAt(target: "workspace", seconds: 2.4, bob: 0.012),
    ])

    /// The four names the design gives Valar, plus the generic.
    ///
    /// Every entry is a sequence and nothing here is a special case in code --
    /// which is the point. A house that grows a fifth tool needs a fifth row,
    /// not a fifth branch.
    static let defaultLibrary: [String: Behavior] = [
        /// Fly to the shelf and wait while the house reads. The payoff is the
        /// book, and phase 3's gate is that the found entry is readable in it.
        "consulting_journal": Behavior(
            primitives: [
                .flyTo(target: "shelf", seconds: 0.9),
                .hoverAt(target: "shelf", seconds: 3.0, bob: 0.010),
            ],
            speakInPlace: true),

        /// Casting about: out to the workspace, a pause, back across it. Reads
        /// as looking for something rather than waiting for something.
        "searching_files": Behavior(primitives: [
            .flyTo(target: "workspace", seconds: 0.6),
            .dwell(seconds: 0.5),
            .hoverAt(target: "workspace", seconds: 1.8, bob: 0.016),
        ]),

        /// Inward rather than outward. Barely moves, hovers high, which is the
        /// spatial version of the face's thinking beats looking up and away.
        "remembering": Behavior(primitives: [
            .flyTo(target: "recall", seconds: 0.8),
            .hoverAt(target: "recall", seconds: 2.6, bob: 0.008),
        ]),

        "working": working,
    ]
}
