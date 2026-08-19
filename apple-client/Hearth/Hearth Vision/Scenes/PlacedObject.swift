//
//  PlacedObject.swift
//  Hearth Vision
//
//  Anything the person has put somewhere in the room, and the shape they all
//  share.
//
//  THE PATTERN, arrived at three times before it was named. The persona has it:
//  `rootEntity` is where she IS, and `modelHost` and `personaAnchor` are how big
//  she is and what travels with her. The bookcase was given it after a
//  pinch-to-scale would have fought `presentationScale` for the same field. The
//  reader needs it because a book you cannot bring closer is a book you cannot
//  read. It is the default for anything spawned or placed from here on.
//
//  An empty ROOT, and the thing itself hanging inside it:
//
//      root            <- gestures move, scale and turn THIS, and only this
//      └── content     <- presentation: its own scale, its own internal offsets
//
//  Two rules fall out, and both were learned by breaking them:
//
//    1. A gesture writes the ROOT. Never the content's transform, because the
//       content's transform is where the content keeps its own business --
//       `presentationScale` lives in `library.root.scale`, and a gesture writing
//       there is two authors on one field with the last write winning.
//    2. A drag is a DELTA from where the grab started, not a follow of where the
//       hand is. Otherwise grabbing a shelf by its edge snaps the whole
//       bookcase's centre onto your fingers.
//
//  And it is what anchoring attaches to. One transform per placed thing, with
//  one meaning: where this is in the room.
//

import Foundation
import RealityKit
import simd

@MainActor
final class PlacedObject {
    /// What gestures move. Add this to the scene; hang the thing inside it.
    let root = Entity()

    /// Where it appears, and where it returns to when it is put away.
    ///
    /// Kept so that closing something and opening it again starts from a known
    /// place rather than from wherever the last one was left. A book you carried
    /// to your desk and finished should not decide where the next one opens.
    private(set) var home: Transform = .init()

    private var startTransform: Transform?
    private var grabPoint: SIMD3<Float>?

    init(named name: String = "PlacedObject") {
        root.name = name
    }

    /// Put it at its starting place, and remember that place.
    func spawn(at position: SIMD3<Float>, facing orientation: simd_quatf = .init()) {
        home = Transform(scale: root.transform.scale,
                         rotation: orientation,
                         translation: position)
        root.transform = home
    }

    /// Back to where it started, for the next time it is needed.
    func returnHome() {
        endGesture()
        root.transform = home
    }

    /// Move it by however far the hand has travelled since the grab began.
    ///
    /// - Parameter onFloor: keep it at the height it already has. True for
    ///   furniture, which stands on the floor and would be lost above the
    ///   ceiling; false for something you are holding, which you want to bring
    ///   up to where you are reading.
    func drag(to point: SIMD3<Float>, onFloor: Bool) {
        if startTransform == nil {
            startTransform = root.transform
            grabPoint = point
        }
        guard let start = startTransform, let grab = grabPoint else { return }
        let moved = point - grab
        root.position = start.translation
            + SIMD3<Float>(moved.x, onFloor ? 0 : moved.y, moved.z)
    }

    /// Let go. The next grab starts from where this one finished.
    func endGesture() {
        startTransform = nil
        grabPoint = nil
    }

    /// Where it is, in the room's own coordinates -- what an anchor remembers.
    var worldTransform: simd_float4x4 { root.transformMatrix(relativeTo: nil) }
}
