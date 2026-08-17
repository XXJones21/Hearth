//
//  PersonaVisualizationTests.swift
//  HearthCoreTests
//
//  The decode, and the two ways a face config can be incomplete. The second
//  and third cases are the ones worth having: both must land on the orb, and
//  the difference between "unknown type" and "face with no geometry" is a
//  distinction the stage has to make without knowing anything about faces.
//

import XCTest
@testable import HearthCore

final class PersonaVisualizationTests: XCTestCase {
    private let faceJSON: [String: Any] = [
        "type": "procedural_face",
        "archetype": "warm_round",
        "geometry": [
            "head_width": 1.0, "head_height": 1.05, "head_roundness": 0.8,
            "eye_size": 0.1, "eye_spacing": 0.38, "eye_height": 0.45,
            "eye_length": 2.4, "eye_tilt": 0.0,
            "mouth_width": 0.34, "mouth_thickness": 0.05, "mouth_curve": 0.26,
        ],
    ]

    func testDecodesProceduralFace() {
        let v = PersonaVisualization.from(visualization: faceJSON, personaName: "Sulivan")
        XCTAssertEqual(v.kind, .proceduralFace)
        XCTAssertTrue(v.canRenderFace)
        XCTAssertEqual(v.faceGeometry?.eyeLength ?? 0, 2.4, accuracy: 1e-9)
        XCTAssertEqual(v.faceGeometry?.eyeSize ?? 0, 0.1, accuracy: 1e-9)
    }

    func testUnknownTypeStillFallsBackToOrb() {
        let v = PersonaVisualization.from(
            visualization: ["type": "holo_projection"], personaName: "X")
        XCTAssertEqual(v.kind, .sphereParticle)
        XCTAssertFalse(v.canRenderFace)
    }

    func testFaceWithoutGeometryDoesNotClaimRenderable() {
        let v = PersonaVisualization.from(
            visualization: ["type": "procedural_face"], personaName: "X")
        XCTAssertEqual(v.kind, .proceduralFace)
        XCTAssertFalse(v.canRenderFace)   // falls back to the orb, like canRenderModel
    }

    /// A house sending its numbers as JSON integers must not silently lose
    /// them: `1` decodes as Int, not Double, and a strict cast would drop the
    /// whole geometry and quietly render the orb instead.
    func testIntegerGeometryValuesDecode() {
        let v = PersonaVisualization.from(
            visualization: ["type": "procedural_face", "geometry": ["head_width": 1]],
            personaName: "X")
        XCTAssertTrue(v.canRenderFace)
        XCTAssertEqual(v.faceGeometry?.headWidth ?? 0, 1.0, accuracy: 1e-9)
        // Everything unstated keeps the archetype default rather than zeroing.
        XCTAssertEqual(v.faceGeometry?.eyeLength ?? 0, 2.4, accuracy: 1e-9)
    }
}
