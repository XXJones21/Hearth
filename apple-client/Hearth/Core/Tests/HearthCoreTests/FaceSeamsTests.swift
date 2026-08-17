//
//  FaceSeamsTests.swift
//  HearthCoreTests
//
//  The two rules that decide what the face is doing, pulled out of the view so
//  they can be asserted instead of eyeballed on a phone: which state it plays,
//  and where it looks.
//

import XCTest
@testable import HearthCore

final class FaceSeamsTests: XCTestCase {

    // MARK: - Which state plays

    func testComposerListensOnlyWhenNothingElseIsHappening() {
        XCTAssertEqual(PersonaFaceView.faceState(for: .IDLE, composerUp: true), .listening)
        XCTAssertEqual(PersonaFaceView.faceState(for: .LOADING, composerUp: true), .listening)
    }

    /// The bug this rule exists for: typing a follow-up while the house is
    /// mid-reply must not park the face in listening through the whole answer.
    func testALiveTurnOutranksTheComposer() {
        XCTAssertEqual(PersonaFaceView.faceState(for: .THINKING, composerUp: true), .thinking)
        XCTAssertEqual(PersonaFaceView.faceState(for: .SPEAKING, composerUp: true), .speaking)
        XCTAssertEqual(PersonaFaceView.faceState(for: .LISTENING, composerUp: true), .listening)
    }

    func testIdleWithoutComposerIsIdle() {
        XCTAssertEqual(PersonaFaceView.faceState(for: .IDLE, composerUp: false), .idle)
        XCTAssertEqual(PersonaFaceView.faceState(for: .LOADING, composerUp: false), .idle)
    }

    // MARK: - Where it looks

    private let face = CGRect(x: 100, y: 100, width: 200, height: 200)   // centre 200,200

    func testNoComposerMeansNoTarget() {
        XCTAssertNil(PersonaFaceView.lookTarget(face: face, composer: nil))
    }

    /// A composer directly below the face pulls the gaze down and not sideways
    /// -- the phone's usual case, which the fixed target used to assume.
    func testComposerBelowPullsTheGazeDown() {
        let composer = CGRect(x: 100, y: 500, width: 200, height: 40)
        let target = PersonaFaceView.lookTarget(face: face, composer: composer)
        XCTAssertNotNil(target)
        XCTAssertEqual(target?.x ?? 1, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(target?.y ?? 0, 0.5)
        XCTAssertEqual(target?.focus ?? 0, 0.5, accuracy: 1e-9)
    }

    /// The case the fixed "straight down" could never express: a composer that
    /// is not centred under the face, as on an iPad or a resized window.
    func testAnOffsetComposerPullsSideways() {
        let composer = CGRect(x: 600, y: 300, width: 200, height: 40)
        let target = PersonaFaceView.lookTarget(face: face, composer: composer)
        XCTAssertGreaterThan(target?.x ?? 0, 0.5)
    }

    func testTargetsStayInsideGazeSpace() {
        let faraway = CGRect(x: 5000, y: 5000, width: 10, height: 10)
        let target = PersonaFaceView.lookTarget(face: face, composer: faraway)
        XCTAssertEqual(target?.x ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(target?.y ?? 0, 1, accuracy: 1e-9)
    }

    /// A face with no size yet (first layout pass) has no centre to measure
    /// from, and dividing by it would hand the director a NaN gaze.
    func testAnUnlaidOutFaceHasNoTarget() {
        let target = PersonaFaceView.lookTarget(
            face: .zero, composer: CGRect(x: 0, y: 100, width: 10, height: 10))
        XCTAssertNil(target)
    }
}
