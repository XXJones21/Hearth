//
//  RoomAnchors.swift
//  Hearth Vision
//
//  Where things stay put. The room remembers what you arranged in it, across
//  launches and across days.
//
//  WHAT ARKIT PERSISTS, AND WHAT IT DOES NOT. A `WorldAnchor` added to a
//  `WorldTrackingProvider` survives the app closing: ARKit keeps its UUID and
//  its pose, and redelivers it through `anchorUpdates` when the person is back
//  in the same place. What ARKit does NOT keep is what the anchor MEANT. Its
//  own documentation is explicit: "It's your app's responsibility to persist
//  additional information, such as the meaning of each anchor." So the mapping
//  from anchor to thing -- this one is the persona, that one is the bookcase --
//  is ours, and it lives in UserDefaults beside nothing else.
//
//  THE RESTORE PATH IS NOT THE IOS ONE, and this is the thing most likely to be
//  written wrong by someone who has done this on a phone. There is no
//  `AnchorEntity(anchor:)` and no `allAnchors` sweep. It is provider
//  redelivery: run the session, read `anchorUpdates`, match the id against what
//  you saved, and apply the transform yourself. Arena learned this the hard way
//  and its comment says so; getting it wrong is a thing that silently never
//  restores.
//
//  ANCHORS ARE LOCAL. Updates only arrive for anchors NEAR the person, so
//  opening Hearth in a different room delivers nothing and the placements fall
//  back to their spawn positions. That is correct rather than broken: a
//  bookcase you left against a wall in the study is not in the kitchen.
//

import Foundation
import Combine
import ARKit
import RealityKit
import simd

/// The things a room can hold a place for.
///
/// An enum rather than free-form ids because the set is small, known, and each
/// member means something specific to restore. A saved id for a slot that no
/// longer exists is simply never matched.
enum RoomSlot: String, CaseIterable, Sendable {
    case persona
    case library
}

@MainActor
final class RoomAnchors: ObservableObject {
    /// Where each slot was left, once ARKit has said so. A slot missing from
    /// here has no remembered place and should use its spawn position.
    @Published private(set) var placements: [RoomSlot: simd_float4x4] = [:]

    /// True once the session is running, so a host can tell "no anchor yet"
    /// from "anchoring is not available at all".
    @Published private(set) var running = false

    private let session = ARKitSession()
    private let worldTracking = WorldTrackingProvider()

    /// slot -> anchor id, ours to keep because ARKit keeps only the id.
    private var saved: [RoomSlot: UUID] = [:]

    private static let storeKey = "hearth.roomAnchors"

    init() {
        saved = Self.loadStore()
    }

    /// Start world tracking and keep applying what it redelivers.
    ///
    /// Degrades quietly and deliberately. The simulator has no world tracking,
    /// and a person may decline world sensing -- in both cases the room still
    /// works, it just forgets where things were. A client that refused to open
    /// its immersive space over that would be trading the whole feature for one
    /// of its conveniences.
    func run() async {
        guard WorldTrackingProvider.isSupported else {
            print("[Anchors] world tracking unsupported; placements will not persist")
            return
        }
        let auth = await session.requestAuthorization(for: [.worldSensing])
        guard auth[.worldSensing] == .allowed else {
            print("[Anchors] world sensing not allowed; placements will not persist")
            return
        }
        do {
            try await session.run([worldTracking])
            running = true
        } catch {
            print("[Anchors] session failed: \(error.localizedDescription)")
            return
        }

        for await update in worldTracking.anchorUpdates {
            let anchor = update.anchor
            guard let slot = saved.first(where: { $0.value == anchor.id })?.key else { continue }
            switch update.event {
            case .added, .updated:
                placements[slot] = anchor.originFromAnchorTransform
            case .removed:
                placements[slot] = nil
            }
        }
    }

    /// Remember where something has been put.
    ///
    /// Replaces whatever that slot was anchored to before, because a thing has
    /// one place at a time and leaving the old anchor behind would have ARKit
    /// tracking a bookcase that is no longer there.
    func remember(_ slot: RoomSlot, at transform: simd_float4x4) {
        guard running else { return }
        let previous = saved[slot]
        let anchor = WorldAnchor(originFromAnchorTransform: transform)
        saved[slot] = anchor.id
        placements[slot] = transform
        Self.saveStore(saved)

        Task {
            if let previous {
                try? await worldTracking.removeAnchor(forID: previous)
            }
            do {
                try await worldTracking.addAnchor(anchor)
            } catch {
                print("[Anchors] could not add \(slot.rawValue): \(error.localizedDescription)")
            }
        }
    }

    /// Forget a slot entirely -- the bookcase put away, not merely moved.
    func forget(_ slot: RoomSlot) {
        let previous = saved.removeValue(forKey: slot)
        placements[slot] = nil
        Self.saveStore(saved)
        guard let previous, running else { return }
        Task { try? await worldTracking.removeAnchor(forID: previous) }
    }

    // MARK: - The store

    private static func loadStore() -> [RoomSlot: UUID] {
        guard let raw = UserDefaults.standard.dictionary(forKey: storeKey) as? [String: String]
        else { return [:] }
        return raw.reduce(into: [:]) { out, pair in
            guard let slot = RoomSlot(rawValue: pair.key), let id = UUID(uuidString: pair.value)
            else { return }
            out[slot] = id
        }
    }

    private static func saveStore(_ store: [RoomSlot: UUID]) {
        let raw = store.reduce(into: [String: String]()) { out, pair in
            out[pair.key.rawValue] = pair.value.uuidString
        }
        UserDefaults.standard.set(raw, forKey: storeKey)
    }
}
