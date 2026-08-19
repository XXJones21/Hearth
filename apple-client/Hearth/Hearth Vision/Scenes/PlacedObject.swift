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
import SwiftUI
import HearthCore

#if canImport(UIKit)
import UIKit
#endif

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

    /// The bar you grab to move it.
    ///
    /// WHY A PLACED THING NEEDS ONE. A gesture reaches an entity through a
    /// collision shape, and an empty root has none -- so a root with only a
    /// SwiftUI attachment hanging off it is not draggable at all. The
    /// attachment itself does not help: it is a hosted view that handles its
    /// own input as SwiftUI, so a `targetedToEntity` drag never sees it. The
    /// reader looked finished and could not be moved for exactly this reason.
    ///
    /// A BAR RATHER THAN THE WHOLE PANEL, and that is the second half of the
    /// answer. A collider covering the panel would sit in front of the buttons
    /// inside it and eat every press -- the same fault that has now bitten this
    /// project three times in three places. So the handle is beneath the
    /// content, where visionOS puts a window's own bar, and it is visible
    /// because an invisible grab area is one you have to be told about.
    private(set) var grabHandle: Entity?

    init(named name: String = "PlacedObject") {
        root.name = name
    }

    /// Give it something to be grabbed by.
    ///
    /// - Parameters:
    ///   - width: how wide the bar is, in metres. Narrower than the content, so
    ///     it reads as a handle rather than as a shelf the content sits on.
    ///   - drop: how far below the content's centre it hangs.
    func addGrabHandle(width: Float, drop: Float) {
        grabHandle?.removeFromParent()

        let size = SIMD3<Float>(width, Self.handleThickness, Self.handleDepth)
        var material = UnlitMaterial()
        material.color = .init(tint: Self.color(HearthPalette.Scene.linen))
        material.blending = .transparent(opacity: 0.55)

        let bar = ModelEntity(mesh: .generateBox(size: size,
                                                 cornerRadius: Self.handleThickness * 0.5),
                              materials: [material])
        bar.name = root.name + ".grab"
        bar.position = SIMD3<Float>(0, -drop, 0)

        #if os(visionOS)
        // Taller than it looks. A 6mm bar is a hard thing to aim at, so the
        // shape it is HIT by is generous where the shape it is DRAWN as is not.
        bar.components.set(CollisionComponent(
            shapes: [.generateBox(size: SIMD3<Float>(width,
                                                     Self.handleThickness * 5,
                                                     Self.handleDepth * 3))]))
        bar.components.set(InputTargetComponent())
        bar.components.set(HoverEffectComponent())
        #endif

        root.addChild(bar)
        grabHandle = bar
    }

    private static let handleThickness: Float = 0.006
    private static let handleDepth: Float = 0.012

    private static func color(_ c: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }

    /// Keep it turned toward whoever is looking at it.
    ///
    /// A panel you can carry around the room but not turn faces whichever way
    /// it spawned, so bringing a book closer and stepping to one side leaves
    /// you reading its edge. `BillboardComponent` is RealityKit's own answer
    /// and is what a SwiftUI window does: the system turns the entity to the
    /// viewer every frame, without the app ever learning where the viewer is --
    /// which matters, because head pose is not something an app should have to
    /// ask for in order to point a page at someone.
    ///
    /// A CHOICE rather than the default, because it is wrong for half of what
    /// gets placed. Furniture stands where you put it: a bookcase that swung to
    /// face you as you crossed the room would be a bookcase you could never put
    /// against a wall. Things you HOLD face you; things you PLACE do not.
    ///
    /// Note that this takes over the entity's orientation, so `spawn(facing:)`
    /// stops meaning anything once it is on -- and `RotateGesture`, when it
    /// arrives in 4.5, belongs to the things that do not billboard.
    func facesViewer(_ on: Bool) {
        if on {
            root.components.set(BillboardComponent())
        } else {
            root.components.remove(BillboardComponent.self)
        }
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

    /// Take it out of the room entirely.
    ///
    /// Closing something has to remove what it was made of, not just what it
    /// was showing. The reader's panel is an attachment and vanishes with the
    /// state that declared it -- but its grab handle is an ENTITY, built here,
    /// and nothing else was going to take it away. So closing a book left a bar
    /// hanging in the air with nothing above it.
    ///
    /// The rule for anything built in `spawn`: it is torn down here. A placed
    /// thing that half-disappears is worse than one that does not disappear at
    /// all, because the leftovers are still grabbable.
    func retire() {
        endGesture()
        grabHandle?.removeFromParent()
        grabHandle = nil
        root.removeFromParent()
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
