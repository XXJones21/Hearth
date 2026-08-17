//
//  UiComponentDescriptor.swift
//  Hearth
//
//  Tolerant model for server-driven generative UI cards (the Valar gateway's
//  `ui_component` payloads). Swift port of the Echo client's
//  `ui/dynamic/UiComponent.kt`. The contract is graceful degradation: unknown
//  keys are ignored, missing keys fall back, and only a missing/blank `type`
//  makes a payload unusable. Unknown component *types* parse fine and simply
//  render nothing downstream (forward compatibility).
//

import Foundation

public struct UiComponentDescriptor: Identifiable {
    /// Unique PER INSTANCE, not per type. The timeline is a transcript, so two
    /// emits of the same type are two separate entries that must both keep
    /// their place in the feed (desktop learned this live 2026-07-31: keying
    /// by type made the earlier card vanish and the newer one "move down").
    public let id: String
    public let type: String
    public let version: Int
    public let props: [String: Any]
    /// When this instance arrived — the feed sorts messages and cards together.
    public let receivedAt: Date

    /// Explicit because a public struct's memberwise init is internal, and the
    /// card library builds sample descriptors from the app target.
    public init(id: String, type: String, version: Int,
                props: [String: Any], receivedAt: Date) {
        self.id = id
        self.type = type
        self.version = version
        self.props = props
        self.receivedAt = receivedAt
    }

    // MARK: - Type constants (mirror the server vocabulary)

    public static let typeClock = "clock"
    public static let typeWeatherCard = "weather_card"
    public static let typeTimerCard = "timer_card"
    public static let typeBriefText = "brief_text"
    public static let typeSlideshow = "slideshow"
    public static let typeCaptions = "captions"
    public static let typeGeneratedView = "generated_view"
    /// A drawing from the local art studio. Lands at submit time, empty, and
    /// settles in place; see ImageCard and EaselStore.
    public static let typeImageCard = "image_card"
    /// A file-access approval the house is WAITING on (see ActionCards).
    public static let typePermissionCard = "permission_card"
    /// A question with persona-authored options (see ActionCards).
    public static let typeChoiceCard = "choice_card"
    public static let supportedVersion = 1

    // MARK: - Parsing

    /// Build a descriptor from a raw JSON payload (`[String: Any]` from
    /// `JSONSerialization`). Returns nil when `type` is missing/blank, or when
    /// the payload declares a version this build does not speak.
    public static func from(_ raw: [String: Any]) -> UiComponentDescriptor? {
        guard let type = (raw["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !type.isEmpty else {
            return nil
        }
        let version = raw["version"] as? Int ?? supportedVersion
        guard version == supportedVersion else { return nil }
        let props = raw["props"] as? [String: Any] ?? [:]
        let now = Date()
        return UiComponentDescriptor(
            id: "\(type)-\(now.timeIntervalSince1970)-\(UUID().uuidString.prefix(6))",
            type: type,
            version: version,
            props: props,
            receivedAt: now
        )
    }

    // MARK: - Defensive prop accessors

    public func str(_ key: String, fallback: String = "") -> String {
        props[key] as? String ?? fallback
    }

    public func int(_ key: String, fallback: Int) -> Int {
        if let i = props[key] as? Int { return i }
        // Server sometimes encodes numbers as strings; tolerate both.
        if let s = props[key] as? String, let i = Int(s) { return i }
        if let d = props[key] as? Double { return Int(d) }
        return fallback
    }

    /// Optional number, tolerating the string/int/double encodings the server
    /// mixes. Nil means "absent", which cards treat as "do not render".
    public func dbl(_ key: String) -> Double? {
        props.optDouble(key)
    }

    /// Nested object, for cards that carry their payload under a key rather
    /// than flat in `props`.
    public func obj(_ key: String) -> [String: Any] {
        props[key] as? [String: Any] ?? [:]
    }

    public func strList(_ key: String) -> [String] {
        guard let arr = props[key] as? [Any] else { return [] }
        return arr.compactMap { $0 as? String }
    }

    public func objList(_ key: String) -> [[String: Any]] {
        guard let arr = props[key] as? [Any] else { return [] }
        return arr.compactMap { $0 as? [String: Any] }
    }

}

// MARK: - Nested-object accessors (for generated_view sections, timer rows, …)

public extension Dictionary where Key == String, Value == Any {
    /// String value for `key`, or "" on miss/wrong type.
    func optString(_ key: String, fallback: String = "") -> String {
        self[key] as? String ?? fallback
    }

    /// Int value for `key`, tolerating string/double encodings.
    func optInt(_ key: String, fallback: Int) -> Int {
        if let i = self[key] as? Int { return i }
        if let s = self[key] as? String, let i = Int(s) { return i }
        if let d = self[key] as? Double { return Int(d) }
        return fallback
    }

    /// Optional number for `key`, tolerating string/int encodings. Nil on miss.
    func optDouble(_ key: String) -> Double? {
        if let d = self[key] as? Double { return d }
        if let i = self[key] as? Int { return Double(i) }
        if let s = self[key] as? String { return Double(s) }
        return nil
    }

    /// Array-of-objects value for `key`, or [] on miss/wrong type.
    func childObjList(_ key: String) -> [[String: Any]] {
        guard let arr = self[key] as? [Any] else { return [] }
        return arr.compactMap { $0 as? [String: Any] }
    }
}

// MARK: - Card notifications

public extension Notification.Name {
    /// A choice_card chip was tapped. The hosting surface decides what
    /// sending means -- ChatViewModel sends the label as the user's turn,
    /// exactly as if they had typed it (the desktop feed's contract).
    ///
    /// Declared here rather than beside the chip that posts it: the poster is
    /// in HearthUI, the observer is ChatViewModel in HearthCore, and the name
    /// is the contract between them. It belongs to the layer both can see.
    static let hearthChoicePicked = Notification.Name("hearth.choicePicked")
}
