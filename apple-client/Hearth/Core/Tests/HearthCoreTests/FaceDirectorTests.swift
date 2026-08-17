//
//  FaceDirectorTests.swift
//  HearthCoreTests
//
//  The desktop's director suite, ported. Every assertion here only passes when
//  the timing tables match the TypeScript: the blink band is the tier's
//  interval, the envelope numbers are laughter's attack/hold/decay. A drifted
//  constant fails as a number rather than as "the face feels off".
//

import XCTest
@testable import HearthCore

final class FaceDirectorTests: XCTestCase {
    let warm = FaceGeometry()

    func testIdleVariesGazeAndBlinksCalm() {
        let d = FaceDirector(geometry: warm, now: 0)
        var gazes = Set<String>()
        var blinks = 0
        var inBlink = false
        var t = 0.0
        while t <= 30_000 {
            let p = d.tick(now: t, state: .idle, cue: nil, speechLevel: 0,
                           reduceMotion: false, lookTarget: nil)
            if t > 2000 { gazes.insert(String(format: "%.2f", p.gazeX)) }
            let closed = p.eyelidL > 0.7
            if closed && !inBlink { blinks += 1; inBlink = true }
            if !closed { inBlink = false }
            t += 16.7
        }
        XCTAssertGreaterThan(gazes.count, 3)
        XCTAssertTrue((3...10).contains(blinks), "calm tier: got \(blinks) blinks in 30s")
    }

    func testTransientEnvelopeLerpsInHoldsAndDecays() {
        let d = FaceDirector(geometry: warm, now: 0)
        _ = d.tick(now: 0, state: .idle, cue: nil, speechLevel: 0,
                   reduceMotion: true, lookTarget: nil)   // snap-settle
        let cue = FaceCue(name: "laughter", at: 100)
        let ramp = d.tick(now: 160, state: .idle, cue: cue, speechLevel: 0,
                          reduceMotion: true, lookTarget: nil)
        XCTAssertTrue(ramp.eyeArc > 0.1 && ramp.eyeArc < 0.9)   // mid-attack
        let hold = d.tick(now: 400, state: .idle, cue: cue, speechLevel: 0,
                          reduceMotion: true, lookTarget: nil)
        XCTAssertGreaterThan(hold.eyeArc, 0.8)
        let gone = d.tick(now: 3200, state: .idle, cue: cue, speechLevel: 0,
                          reduceMotion: true, lookTarget: nil)
        XCTAssertLessThan(gone.eyeArc, 0.05)
    }

    func testSpeechOpensRoundMouthAndListeningWatchesTarget() {
        let d = FaceDirector(geometry: warm, now: 0)
        let talk = d.tick(now: 50, state: .speaking, cue: nil, speechLevel: 0.5,
                          reduceMotion: true, lookTarget: nil)
        XCTAssertGreaterThanOrEqual(talk.mouthOpen, 0.45)
        XCTAssertEqual(talk[.mouthRound], 1, accuracy: 1e-9)
        let watch = d.tick(now: 5000, state: .listening, cue: nil, speechLevel: 0,
                           reduceMotion: true,
                           lookTarget: LookTarget(x: 0, y: 0.9, focus: 0.5))
        XCTAssertGreaterThan(watch[.gazeY], 0.5)   // pulled toward the target
    }

    func testReduceMotionSuppressesBlink() {
        let d = FaceDirector(geometry: warm, now: 0)
        var t = 0.0
        var closed = false
        while t <= 20_000 {
            let p = d.tick(now: t, state: .idle, cue: nil, speechLevel: 0,
                           reduceMotion: true, lookTarget: nil)
            if p.eyelidL > 0.5 { closed = true }
            t += 16.7
        }
        XCTAssertFalse(closed)
    }

    /// Entering a state restarts its playlist, so a face that has been idle
    /// for a minute does not open its thinking beat mid-phrase.
    func testStateChangeRestartsThePlaylist() {
        let d = FaceDirector(geometry: warm, now: 0)
        var t = 0.0
        while t <= 12_000 {
            _ = d.tick(now: t, state: .idle, cue: nil, speechLevel: 0,
                       reduceMotion: true, lookTarget: nil)
            t += 16.7
        }
        // The first thinking frame is the first beat: eyes shortened, thrown
        // up and to the right. Reduce motion snaps, so one tick is enough.
        let first = d.tick(now: t, state: .thinking, cue: nil, speechLevel: 0,
                           reduceMotion: true, lookTarget: nil)
        XCTAssertGreaterThan(first.gazeX, 0.5)
        XCTAssertLessThan(first.gazeY, -0.3)
        XCTAssertLessThan(first.eyeLength, warm.eyeLength)
    }

    /// An unknown cue still runs an envelope (the default profile) and simply
    /// poses nothing, rather than freezing the face or crashing on lookup.
    func testUnknownCueIsHarmless() {
        let d = FaceDirector(geometry: warm, now: 0)
        let p = d.tick(now: 200, state: .idle, cue: FaceCue(name: "exasperation", at: 100),
                       speechLevel: 0, reduceMotion: true, lookTarget: nil)
        XCTAssertEqual(p.eyelidL, 0, accuracy: 1e-9)
        XCTAssertEqual(p.eyeArc, 0, accuracy: 1e-9)
    }
}
