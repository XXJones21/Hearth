//
//  SharedSnapshot.swift
//  Hearth  (shared by the app target AND the Hearth WidgetExtension target)
//
//  The small, Codable state the app publishes into the App Group container for
//  its widgets to read. The app writes it on meaningful changes and calls
//  WidgetCenter.shared.reloadAllTimelines(); the widget's timeline provider
//  reads it back. Widgets are static SwiftUI snapshots, so this stays tiny —
//  just what the glanceable widgets render (persona, connection, last session
//  summary, and active timers whose countdowns run client-side via
//  Text(timerInterval:)).
//
//  IMPORTANT: this file must be a member of BOTH targets. In Xcode select it
//  and tick "Hearth WidgetExtension" under Target Membership (the same applies
//  to PersonaCanvasView.swift, which the widget reuses to draw Sulivan).
//

import Foundation

/// The glanceable state shared with widgets.
struct HearthSnapshot: Codable {
    var personaName: String
    var connected: Bool
    var state: String                 // "idle" | "listening" | "thinking" | "speaking"
    var sessionSummary: String?
    var sessionSummaryDate: Date?
    /// The live generative-UI cards, flattened for the widget carousel.
    var cards: [CardSummary]
    var updatedAt: Date

    /// A compact, widget-renderable view of one card (the widget doesn't host
    /// the full DynamicComponent renderers; the app flattens cards to this).
    struct CardSummary: Codable, Identifiable {
        var type: String              // weather_card | timer_card | brief_text | ...
        var symbol: String            // SF Symbol for the card
        var title: String             // primary line
        var subtitle: String          // secondary line
        var detail: String            // body / tertiary
        var fireAt: Date?             // timer countdown via Text(timerInterval:)
        var id: String { "\(type)#\(title)#\(subtitle)#\(fireAt.map { Int($0.timeIntervalSince1970) } ?? 0)" }
    }

    static let placeholder = HearthSnapshot(
        personaName: "Sulivan",
        connected: false,
        state: "idle",
        sessionSummary: nil,
        sessionSummaryDate: nil,
        cards: [],
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

/// Read/write the snapshot in the shared App Group container.
enum SharedStore {
    /// Must match the App Group id added to both targets in Xcode.
    static let appGroupID = "group.com.joshuajones.Hearth"
    private static let key = "hearth.snapshot.v1"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// App side: persist the latest snapshot. No-op if the App Group is missing.
    static func write(_ snapshot: HearthSnapshot) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    /// Widget side: load the latest snapshot (placeholder if none/undecodable).
    static func read() -> HearthSnapshot {
        guard let defaults,
              let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(HearthSnapshot.self, from: data)
        else { return .placeholder }
        return snapshot
    }
}
