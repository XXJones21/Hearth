//
//  FaceExpressionsTests.swift
//  HearthCoreTests
//
//  The desktop's verify suite, ported. These are invariants rather than value
//  assertions on purpose: they say what each expression MEANS (proportional,
//  clamped, asymmetric where it should be), so a mistyped delta in the port
//  fails here rather than looking slightly wrong on a phone six weeks later.
//

import XCTest
@testable import HearthCore

final class FaceExpressionsTests: XCTestCase {
    let warm = FaceGeometry()                    // defaults ARE warm_round

    /// narrow_precise, from backend/personas/_visual/archetypes.json.
    var narrow: FaceGeometry {
        var g = FaceGeometry()
        g.headWidth = 0.86; g.headHeight = 1.14; g.headRoundness = 0.55
        g.eyeSize = 0.075; g.eyeSpacing = 0.34; g.eyeHeight = 0.44
        g.eyeLength = 2.9; g.eyeTilt = 0.05
        g.mouthWidth = 0.26; g.mouthThickness = 0.04; g.mouthCurve = 0.05
        return g
    }

    /// The whole reason expressions are deltas: two personas with different
    /// eyes get the same PROPORTIONAL change, not the same eyes.
    func testListeningLengthensProportionally() {
        let wl = applyExpression(neutralPose(warm), FACE_EXPRESSIONS[.listening]!, weight: 1)
        let nl = applyExpression(neutralPose(narrow), FACE_EXPRESSIONS[.listening]!, weight: 1)
        let fw = wl.eyeLength / warm.eyeLength
        let fn = nl.eyeLength / narrow.eyeLength
        XCTAssertEqual(fw, fn, accuracy: 1e-9)
        XCTAssertGreaterThan(fw, 1)
        XCTAssertNotEqual(wl.eyeLength, nl.eyeLength, accuracy: 1e-6)
    }

    func testWeightZeroIsIdentityAndClampsHold() {
        let p = applyExpression(neutralPose(warm), FACE_EXPRESSIONS[.surprise]!, weight: 0)
        XCTAssertEqual(p.eyeScaleL, 1, accuracy: 1e-9)
        let layered = applyExpression(
            applyExpression(neutralPose(warm), FACE_EXPRESSIONS[.laughter]!, weight: 1),
            FACE_EXPRESSIONS[.blink]!, weight: 1)
        XCTAssertEqual(layered.eyelidL, 1, accuracy: 1e-9)   // clamped
    }

    func testCharacterInvariants() {
        let sighed = applyExpression(neutralPose(warm), FACE_EXPRESSIONS[.sigh]!, weight: 1)
        XCTAssertLessThan(sighed.eyeArc, -0.5)               // pensive droop
        XCTAssertLessThan(sighed.eyeTiltL, 0); XCTAssertGreaterThan(sighed.eyeTiltR, 0)
        let q = applyExpression(neutralPose(warm), FACE_EXPRESSIONS[.question]!, weight: 1)
        XCTAssertLessThan(q.eyeScaleR, q.eyeScaleL)          // one eye smaller
        let s = applyExpression(neutralPose(warm), FACE_EXPRESSIONS[.surprise]!, weight: 1)
        XCTAssertEqual(s.eyeScaleL, s.eyeScaleR, accuracy: 1e-9)  // symmetric stare
        XCTAssertGreaterThan(s.focus, 0.2)                   // converged
        let d = applyExpression(neutralPose(warm), FACE_EXPRESSIONS[.dissatisfaction]!, weight: 1)
        XCTAssertEqual(d.eyelidL, d.eyelidR, accuracy: 1e-9) // level, side-eyed
        XCTAssertGreaterThan(d.gazeX, 0.5)
    }

    /// A harness ahead of this client names something unknown. The face must
    /// go on wearing the pose it had, not break and not invent one.
    func testUnknownNameIsInert() {
        let base = applyExpression(neutralPose(warm), FACE_EXPRESSIONS[.listening]!, weight: 1)
        let out = applyNamedExpression(base, "exasperation", weight: 1)
        XCTAssertEqual(out.eyeLength, base.eyeLength, accuracy: 1e-9)
        XCTAssertEqual(out.eyelidL, base.eyelidL, accuracy: 1e-9)
    }

    /// Every name the library declares resolves to an entry: a case added to
    /// the enum without a table row would silently become neutral.
    func testEveryNameHasAnExpression() {
        for name in ExpressionName.allCases {
            XCTAssertNotNil(FACE_EXPRESSIONS[name], "no expression for \(name.rawValue)")
        }
    }
}
