//
//  RoomMesh.swift
//  Hearth Vision
//
//  The real room, as geometry the renderer can use.
//
//  ARKit's `SceneReconstructionProvider` streams a mesh of the actual walls,
//  floor and furniture. Every anchor becomes a `ModelEntity` wearing
//  `OcclusionMaterial()` -- invisible, so what you see through it is
//  passthrough, but PRESENT, so it hides virtual things behind it and gives
//  light something to land on.
//
//  WHY IT IS A DEPENDENCY OF THE LIGHT AND NOT A NICETY. Valinor learned this
//  and left the note in its file: `SurroundingsLight` on its own adds flat
//  illumination with no pattern, because a projection needs a real surface to
//  fall on. Without the mesh, a light in the room lights nothing you can see.
//
//  WHAT IT CHANGES THAT NOBODY ASKS FOR. Occlusion is not additive. The moment
//  real geometry occludes, anything placed can be EATEN by it -- a bookcase
//  anchored against a wall loses the half that is inside the wall, a reader
//  pulled close to a table sinks into it, a persona standing where the mesh
//  thinks a sofa is loses her legs. None of that is new; it is the same
//  placement, drawn honestly for the first time. It will still read as a
//  regression on the first run.
//
//  It needs no new Info.plist key: `NSWorldSensingUsageDescription` already
//  covers this, and the justification comment there -- which says the key is
//  for anchors rather than surfaces -- stops being true when this lands.
//

import Foundation
import ARKit
import RealityKit

@MainActor
final class RoomMesh {
    /// Everything reconstructed hangs here. Add it to the immersive scene.
    let root = Entity()

    private let session = ARKitSession()
    private let provider = SceneReconstructionProvider()
    private var pieces: [UUID: ModelEntity] = [:]

    /// The group every reconstructed surface belongs to.
    ///
    /// Its own group so a raycast can ask about THE ROOM and get the room --
    /// not the persona, not the bookcase, not a grab handle. Without it, a test
    /// for "is there a wall between here and there" answers yes the moment it
    /// meets the thing being moved.
    static let surfaces = CollisionGroup(rawValue: 1 << 8)

    /// Give a reconstructed surface a shape things can be stopped by.
    ///
    /// OCCLUSION IS NOT COLLISION, which is the thing the first run made plain:
    /// a persona shoved at a wall disappeared INTO it, correctly hidden and
    /// completely unimpeded. Occlusion decides what you can see; it has nothing
    /// to say about where anything is. A wall you can see through your persona
    /// but walk her through is worse than no wall at all, because the room now
    /// looks like it has rules and does not.
    ///
    /// Static, because the room does not move -- and the shape is generated
    /// from the anchor rather than from the render mesh, which is what
    /// `generateStaticMesh(from:)` exists for.
    private static func giveCollision(_ piece: ModelEntity, from anchor: MeshAnchor) async {
        guard let shape = try? await ShapeResource.generateStaticMesh(from: anchor) else { return }
        piece.components.set(CollisionComponent(
            shapes: [shape],
            isStatic: true,
            filter: CollisionFilter(group: surfaces, mask: .all)))
    }

    /// A SECOND session, and deliberately not RoomAnchors'. A provider can only
    /// be run once, and the two have different lifetimes: anchors are wanted the
    /// moment the room opens and for as long as it is open, while the mesh is a
    /// continuous cost that should be startable and stoppable on its own.
    /// They share the one authorisation, which is granted per type and not per
    /// session.
    func run() async {
        guard SceneReconstructionProvider.isSupported else {
            print("[RoomMesh] scene reconstruction unsupported here; no occlusion")
            return
        }
        do {
            try await session.run([provider])
        } catch {
            print("[RoomMesh] session failed: \(error.localizedDescription)")
            return
        }

        for await update in provider.anchorUpdates {
            let anchor = update.anchor
            switch update.event {
            case .added, .updated:
                guard let mesh = try? await MeshResource(from: anchor) else { continue }
                if let existing = pieces[anchor.id] {
                    existing.model?.mesh = mesh
                    existing.transform = Transform(matrix: anchor.originFromAnchorTransform)
                    await Self.giveCollision(existing, from: anchor)
                } else {
                    let piece = ModelEntity(mesh: mesh, materials: [OcclusionMaterial()])
                    piece.transform = Transform(matrix: anchor.originFromAnchorTransform)
                    await Self.giveCollision(piece, from: anchor)
                    pieces[anchor.id] = piece
                    root.addChild(piece)
                    if pieces.count == 1 { print("[RoomMesh] first room surface arrived") }
                }
            case .removed:
                pieces[anchor.id]?.removeFromParent()
                pieces[anchor.id] = nil
            }
        }
    }
}
