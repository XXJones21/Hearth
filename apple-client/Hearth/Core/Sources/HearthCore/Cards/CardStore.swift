//
//  CardStore.swift
//  Hearth
//
//  Holds the generative UI cards driven by the Valar gateway's `ui_component`
//  messages. The op vocabulary is Echo's (`upsert` / `clear` / `clear_all`; an
//  absent op means upsert), but the RETENTION model is the desktop's as of
//  2026-07-31: cards are TRANSCRIPT HISTORY, not a status board. Every upsert
//  appends a NEW instance — a re-emit of a type never replaces or moves the
//  card the user already scrolled past. The list is capped at `maxCards` to
//  bound memory. `clear` still drops every instance of a type.
//
//  Exception: `session_gallery` is a transient picker, not a transcript entry,
//  so it stays one-per-type (see `singletonTypes`).
//

import Foundation
import Combine

@MainActor
final class CardStore: ObservableObject {
    /// Card history, oldest first. Many instances per type are expected.
    @Published private(set) var cards: [UiComponentDescriptor] = []

    /// Matches the desktop's `slice(-40)`.
    private static let maxCards = 40

    /// Types that are UI surfaces rather than transcript entries: a second
    /// emit replaces the first instead of stacking a duplicate.
    private static let singletonTypes: Set<String> = [
        UiComponentDescriptor.typeSessionGallery
    ]

    /// Pending expiry tasks, keyed by card INSTANCE id.
    private var ttlTasks: [String: Task<Void, Never>] = [:]

    // MARK: - Apply a raw ui_component payload

    func apply(_ raw: [String: Any]) {
        let op = raw.optString("op", fallback: "upsert")

        switch op {
        case "clear":
            let type = (raw["type"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !type.isEmpty else { return }
            dismissType(type)
            print("[UI] clear type=\(type)")
            return

        case "clear_all":
            cancelAllTtl()
            cards.removeAll()
            print("[UI] clear_all")
            return

        case "upsert":
            break

        default:
            // Unknown op: ignore (forward compatibility).
            return
        }

        guard let descriptor = UiComponentDescriptor.from(raw) else {
            print("[UI] ui_component payload unusable (bad type or version); ignored")
            return
        }

        if Self.singletonTypes.contains(descriptor.type) {
            dismissType(descriptor.type)
        }

        cards.append(descriptor)
        if cards.count > Self.maxCards {
            let dropped = cards.prefix(cards.count - Self.maxCards)
            for card in dropped { cancelTtl(for: card.id) }
            cards.removeFirst(cards.count - Self.maxCards)
        }
        print("[UI] append type=\(descriptor.type) v=\(descriptor.version) (\(cards.count) in feed)")

        scheduleTtlIfNeeded(raw, id: descriptor.id, type: descriptor.type)
    }

    func clearAll() {
        cancelAllTtl()
        cards.removeAll()
    }

    /// Manually dismiss a single card instance (close button, gallery pick).
    func dismiss(_ id: UiComponentDescriptor.ID) {
        cancelTtl(for: id)
        cards.removeAll { $0.id == id }
    }

    /// Drop every instance of a type (the `clear` op, and singleton replacement).
    func dismissType(_ type: String) {
        for card in cards where card.type == type { cancelTtl(for: card.id) }
        cards.removeAll { $0.type == type }
    }

    // MARK: - TTL expiry

    private func scheduleTtlIfNeeded(_ raw: [String: Any], id: String, type: String) {
        guard let ttl = ttlSeconds(raw), ttl > 0 else { return }
        let nanos = UInt64(ttl * 1_000_000_000)
        ttlTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.cards.removeAll { $0.id == id }
                self.ttlTasks[id] = nil
                print("[UI] expired type=\(type) (ttl=\(ttl)s)")
            }
        }
    }

    /// `ttl_s` is a top-level field; tolerate number or numeric string.
    private func ttlSeconds(_ raw: [String: Any]) -> Double? {
        if let d = raw["ttl_s"] as? Double { return d }
        if let i = raw["ttl_s"] as? Int { return Double(i) }
        if let s = raw["ttl_s"] as? String { return Double(s) }
        return nil
    }

    private func cancelTtl(for id: String) {
        ttlTasks[id]?.cancel()
        ttlTasks[id] = nil
    }

    private func cancelAllTtl() {
        for task in ttlTasks.values { task.cancel() }
        ttlTasks.removeAll()
    }
}
