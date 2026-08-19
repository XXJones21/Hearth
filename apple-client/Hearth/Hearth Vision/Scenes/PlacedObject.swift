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
import HearthSpatial

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
    private var startScale: SIMD3<Float>?
    private var startRotation: simd_quatf?
    private var targetRotation: simd_quatf?

    /// True while this thing is being moved, resized or turned.
    ///
    /// So a host can keep OTHER gestures off it while it is. Reaching for a
    /// bookcase and coming away holding one of its books is the failure this
    /// prevents, and it is not hypothetical -- the drag and the tap are both
    /// pinches, aimed at the same furniture, a few centimetres apart.
    var isManipulating: Bool {
        startTransform != nil || startScale != nil || startRotation != nil
    }

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
        // Its own clock, so a placement eases whatever scene it is added to
        // without the host owning a subscription for it. The same lesson the
        // rig learned in phase 4: a subscription belongs to the scene that
        // issued it, and a placement outlives scenes.
        root.components.set(ClosureComponent { [weak self] deltaTime in
            self?.tick(deltaTime: deltaTime)
        })
    }

    /// Ease the root toward the orientation the last twist asked for.
    ///
    /// A rotation read straight from the gesture every frame is exactly as
    /// steady as the two hands reporting it, and a twist in mid-air is not
    /// steady -- the bookcase judders as it comes round. Frame-rate independent
    /// for the same reason the persona's resize is: a fixed per-frame fraction
    /// turns at one speed at 90Hz and another when the room is busy.
    private func tick(deltaTime: TimeInterval) {
        guard let target = targetRotation else { return }
        let current = root.transform.rotation
        // The dot of two unit quaternions is the cosine of half the angle
        // between them, so this is "near enough to stop" without a conversion.
        if abs(simd_dot(current.vector, target.vector)) > 0.99999 {
            root.transform.rotation = target
            targetRotation = nil
            return
        }
        let blend = 1 - pow(Self.turnRetention, Float(max(deltaTime, 0.0001)) * 60)
        root.transform.rotation = simd_slerp(current, target, blend)
    }

    /// How much of the gap to the target survives each 60Hz frame.
    private static let turnRetention: Float = 0.75

    /// Give it something to be grabbed by.
    ///
    /// A VERTICAL BAR DOWN THE LEFT SIDE, like the spine of a book stood on a
    /// shelf, standing off the object rather than touching it. The first cut
    /// put a horizontal bar under the reader and later above the bookcase, and
    /// both were wrong in the same way: a handle that spans the thing's WIDTH
    /// is a handle that has to move whenever the thing is a different size, and
    /// on a bookcase it ended up either at your ankles or over your head.
    ///
    /// A spine is the same shape whatever it is attached to, sits where a hand
    /// naturally goes, and -- because it is beside the object and not in front
    /// of it -- cannot cover anything you might want to press. That last part
    /// is the constraint that keeps reappearing: a collider over the things
    /// people press eats every press.
    ///
    /// - Parameters:
    ///   - height: how tall the bar is, in metres.
    ///   - position: where its centre sits in the placement's own space. The
    ///     caller works this out from the thing it is attached to, because only
    ///     the caller knows how wide that thing is.
    func addGrabHandle(height: Float, at position: SIMD3<Float>) {
        grabHandle?.removeFromParent()

        let size = SIMD3<Float>(Self.handleThickness, height, Self.handleDepth)
        var material = UnlitMaterial()
        material.color = .init(tint: Self.color(HearthPalette.Scene.linen))
        material.blending = .transparent(opacity: 0.55)

        let bar = ModelEntity(mesh: .generateBox(size: size,
                                                 cornerRadius: Self.handleThickness * 0.5),
                              materials: [material])
        bar.name = root.name + ".grab"
        bar.position = position

        #if os(visionOS)
        // Wider than it looks. A 6mm bar is a hard thing to aim at, so the
        // shape it is HIT by is generous where the shape it is DRAWN as is not.
        bar.components.set(CollisionComponent(
            shapes: [.generateBox(size: SIMD3<Float>(Self.handleThickness * 8,
                                                     height,
                                                     Self.handleDepth * 4))]))
        bar.components.set(InputTargetComponent())
        bar.components.set(HoverEffectComponent())
        #endif

        root.addChild(bar)
        grabHandle = bar
        handleAnchor = position
        handleTop = position.y + height * 0.5
    }

    /// Where the grab bar's centre is, in the placement's space.
    ///
    /// Published so that anything else hung beside the object -- a close button
    /// especially -- lines up with the handle instead of carrying its own
    /// separate guess at where the left-hand side is. Two numbers meaning "the
    /// left of this thing" is two numbers to keep in step.
    private(set) var handleAnchor: SIMD3<Float> = .zero

    /// The top of the grab bar, in the placement's space.
    private(set) var handleTop: Float = 0

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
        targetRotation = nil
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
        // A turn still easing would otherwise keep running against a thing that
        // has been taken out of the room.
        targetRotation = nil
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

    /// Resize it, by however much the pinch has spread since it began.
    ///
    /// The ROOT's scale, which is the whole reason the root exists. The content
    /// inside keeps its own -- `library.presentationScale` is what holds the
    /// bookcase's geometry at life size while it is SHOWN at whatever size the
    /// room wants -- and two authors on one field is the bug this pattern was
    /// named to prevent.
    ///
    /// A DELTA from the scale at the start of the pinch, for the same reason a
    /// drag is a delta from the grab: `MagnifyGesture` reports magnification
    /// relative to where the gesture began, so multiplying the live scale by it
    /// every frame compounds and the bookcase runs away.
    ///
    /// Bounded, because the input is not. A pinch can report any magnification
    /// and there is no size at which RealityKit objects -- so without a clamp
    /// the room can be given a bookcase the size of a house, or one too small
    /// to find again in order to undo it. Recovery matters more than range.
    func magnify(by magnification: CGFloat) {
        if startScale == nil { startScale = root.transform.scale }
        guard let start = startScale else { return }
        let factor = Float(max(magnification, 0.0001))
        root.transform.scale = simd_clamp(start * factor,
                                          SIMD3<Float>(repeating: Self.scaleRange.lowerBound),
                                          SIMD3<Float>(repeating: Self.scaleRange.upperBound))
    }

    /// Turn it, about the vertical axis and no other.
    ///
    /// YAW ONLY, and that is a decision rather than a limitation of the
    /// gesture. The one degree of freedom that matters for something standing
    /// in a room is which way it faces; a bookcase lying on its side is not a
    /// thing anyone reaches for, and every extra axis is another way for a
    /// two-finger twist to leave furniture somewhere it has to be rescued from.
    ///
    /// Refused outright for anything that billboards. `facesViewer(true)` hands
    /// the entity's orientation to RealityKit, which rewrites it every frame --
    /// so a turn applied here would be silently undone before it was seen, and
    /// a gesture that does nothing is worse than one that is not offered.
    func turn(by angle: Angle) {
        guard root.components[BillboardComponent.self] == nil else { return }
        if startRotation == nil { startRotation = root.transform.rotation }
        guard let start = startRotation else { return }
        // NOT negated, on the device's word. The first cut reasoned that a
        // clockwise twist should turn the object clockwise seen from above and
        // that +Y yaw runs counter-clockwise, so it flipped the sign -- and on
        // the headset the bookcase turned the wrong way. `RotateGesture`
        // already reports the angle in the sense the hand means it. The
        // reasoning was tidy and the room disagreed.
        targetRotation = start * simd_quatf(angle: Float(angle.radians),
                                            axis: SIMD3<Float>(0, 1, 0))
    }

    /// Put it back to a size it was remembered at.
    ///
    /// Restoring is not a gesture and must not go through one: `magnify` is
    /// relative to a pinch in progress, and there is no pinch here.
    func resize(to scale: Float) {
        root.transform.scale = SIMD3<Float>(repeating:
            min(max(scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound))
    }

    /// How far a placed thing may be pinched from the size it was authored at.
    static let scaleRange: ClosedRange<Float> = 0.3...2.5

    /// Let go. The next grab starts from where this one finished, and a turn
    /// still in flight is allowed to finish -- which is what makes the last
    /// frame of a gesture read as the end of a movement rather than a stop.
    func endGesture() {
        startTransform = nil
        grabPoint = nil
        startScale = nil
        startRotation = nil
    }

    /// Where it is, in the room's own coordinates.
    var worldTransform: simd_float4x4 { root.transformMatrix(relativeTo: nil) }

    /// Where it is and which way it faces, with the size taken back out --
    /// what an anchor can actually hold.
    ///
    /// A `WorldAnchor` is a POSE. `WorldAnchor(originFromAnchorTransform:)`
    /// takes a matrix, which reads as though it takes a transform, and it does
    /// not: ARKit tracks a position and an orientation in the room and there is
    /// nowhere in it for a scale to live. Handing it a scaled matrix therefore
    /// does not fail -- it quietly returns something else tomorrow.
    ///
    /// So the size travels separately (see `placedScale` and `RoomAnchors`) and
    /// this hands over the part the anchor can keep, with the basis normalised
    /// rather than merely hoped to be unit length.
    var worldPose: simd_float4x4 {
        var m = worldTransform
        for column in 0..<3 {
            let axis = SIMD3<Float>(m[column].x, m[column].y, m[column].z)
            let length = simd_length(axis)
            guard length > 0.0001 else { continue }
            let unit = axis / length
            m[column] = SIMD4<Float>(unit.x, unit.y, unit.z, m[column].w)
        }
        return m
    }

    /// The size the person left it at, for the store that remembers what the
    /// anchor cannot.
    var placedScale: Float { root.transform.scale.x }
}
