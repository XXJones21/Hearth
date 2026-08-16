//
//  SessionModels.swift
//  Hearth
//
//  Earlier conversations, from the two places the house keeps them. Records
//  (`GET /sessions`) are what the house has actually said, written one turn at
//  a time as it happens -- including the chat from four minutes ago that no
//  diary exists for yet. Journal entries (`GET /journal/sessions`) are what it
//  later wrote up. A conversation that has been through both appears once, as
//  its record, because the record is the one that can still be resumed turn
//  for turn. Mirrors the desktop rail's mergeRows (SessionsTab.tsx).
//

import Foundation

// MARK: - Wire shapes

/// One row of `GET /sessions`. Tolerant decode: a missing field falls back
/// rather than sinking the whole list.
public struct SessionRecord: Decodable, Identifiable {
    public let sessionId: String
    public let date: String
    public let title: String
    public let persona: String
    public let turns: Int
    public let startedAt: String
    public let hasTranscript: Bool
    public let synced: Bool
    public let thoughtSlug: String

    public var id: String { sessionId }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case date, title, persona, turns
        case startedAt = "started_at"
        case hasTranscript = "has_transcript"
        case synced
        case thoughtSlug = "thought_slug"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = (try? c.decode(String.self, forKey: .sessionId)) ?? ""
        date = (try? c.decode(String.self, forKey: .date)) ?? ""
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        persona = (try? c.decode(String.self, forKey: .persona)) ?? ""
        turns = (try? c.decode(Int.self, forKey: .turns)) ?? 0
        startedAt = (try? c.decode(String.self, forKey: .startedAt)) ?? ""
        // Absent means resumable, matching desktop's `has_transcript !== false`.
        hasTranscript = (try? c.decode(Bool.self, forKey: .hasTranscript)) ?? true
        synced = (try? c.decode(Bool.self, forKey: .synced)) ?? false
        thoughtSlug = (try? c.decode(String.self, forKey: .thoughtSlug)) ?? ""
    }
}

/// One row of `GET /journal/sessions` -- only what the list needs.
public struct JournalSessionRow: Decodable, Identifiable {
    public let slug: String
    public let title: String
    public let date: String
    public let persona: String
    public let summary: String
    public let hasTranscript: Bool

    public var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, title, date, persona, summary
        case hasTranscript = "has_transcript"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = (try? c.decode(String.self, forKey: .slug)) ?? ""
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        date = (try? c.decode(String.self, forKey: .date)) ?? ""
        persona = (try? c.decode(String.self, forKey: .persona)) ?? ""
        summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        hasTranscript = (try? c.decode(Bool.self, forKey: .hasTranscript)) ?? false
    }
}

// MARK: - Merged rows

/// Two sources, one list. `id` is what resume sends: a record's own
/// session_id, or a journal entry's diary slug.
public struct SessionRow: Identifiable {
    public enum Kind { case record, journal }

    public let kind: Kind
    public let rowId: String
    public let date: String
    public let title: String
    public let persona: String
    public let resumable: Bool
    public let turns: Int?
    public let synced: Bool?
    public let summary: String

    public var id: String { "\(kind == .record ? "rec" : "jrn"):\(rowId)" }
}

public enum SessionMerge {
    /// Desktop's mergeRows: records first; journal entries whose diary a
    /// record already claims (thought_slug) are skipped so one conversation
    /// never shows twice. Sorted newest first.
    public static func rows(
        records: [SessionRecord], journal: [JournalSessionRow]
    ) -> [SessionRow] {
        let claimed = Set(
            records.map { $0.thoughtSlug.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
        var rows: [SessionRow] = records.map { r in
            SessionRow(
                kind: .record,
                rowId: r.sessionId,
                date: bestDate(r.date, fallback: String(r.startedAt.prefix(10))),
                title: r.title.isEmpty ? "Untitled session" : r.title,
                persona: r.persona,
                resumable: r.hasTranscript,
                turns: r.turns,
                synced: r.synced,
                summary: ""
            )
        }
        for s in journal where !claimed.contains(s.slug) {
            rows.append(SessionRow(
                kind: .journal,
                rowId: s.slug,
                date: journalDate(s),
                title: rowTitle(s),
                persona: s.persona,
                resumable: s.hasTranscript,
                turns: nil,
                synced: nil,
                summary: s.summary
            ))
        }
        rows.sort { $0.date > $1.date }
        return rows
    }

    /// Rows grouped by day, newest day first, capped like the desktop rail.
    public static func grouped(_ rows: [SessionRow], cap: Int = 40)
        -> [(date: String, items: [SessionRow])]
    {
        var order: [String] = []
        var map: [String: [SessionRow]] = [:]
        for row in rows.prefix(cap) {
            if map[row.date] == nil { order.append(row.date) }
            map[row.date, default: []].append(row)
        }
        return order.sorted(by: >).map { ($0, map[$0] ?? []) }
    }

    private static func bestDate(_ date: String, fallback: String) -> String {
        if !date.isEmpty { return date }
        return fallback.isEmpty ? "Unknown" : fallback
    }

    /// A journal row's date, recovered from the slug when the field is not a
    /// plain day.
    private static func journalDate(_ s: JournalSessionRow) -> String {
        if s.date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            return s.date
        }
        if let r = s.slug.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            return String(s.slug[r])
        }
        return "Unknown"
    }

    /// Desktop's rowTitle: a generic title ("Voice session", "Untitled")
    /// yields to the summary's opening words, trimmed at a word boundary.
    private static func rowTitle(_ s: JournalSessionRow) -> String {
        let t = s.title.trimmingCharacters(in: .whitespaces)
        let generic = t.isEmpty
            || ["voice session", "untitled", "untitled session"].contains(t.lowercased())
        if !generic { return t }
        var line = s.summary
        if let r = line.range(of: #"^(operator|user):\s*"#,
                              options: [.regularExpression, .caseInsensitive]) {
            line.removeSubrange(r)
        }
        line = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if line.isEmpty { return t.isEmpty ? "Untitled session" : t }
        if line.count <= 56 { return line }
        let cut = String(line.prefix(56))
        if let space = cut.lastIndex(of: " ") {
            return String(cut[..<space])
        }
        return cut
    }
}

// MARK: - Loader

@MainActor
public final class SessionsStore: ObservableObject {
    public init() {}

    @Published public private(set) var rows: [SessionRow] = []
    @Published public private(set) var isLoading = false
    /// True only when BOTH sources failed; either alone still makes a list.
    @Published public private(set) var unreachable = false
    @Published public private(set) var hasLoaded = false

    public func load() async {
        guard !isLoading else { return }
        isLoading = true

        async let records: [SessionRecord]? = Self.list("/sessions")
        async let journal: [JournalSessionRow]? = Self.list("/journal/sessions?limit=200")
        let (r, j) = await (records, journal)

        rows = SessionMerge.rows(records: r ?? [], journal: j ?? [])
        unreachable = r == nil && j == nil
        hasLoaded = true
        isLoading = false
    }

    /// Both endpoints answer `{"sessions": [...]}`.
    private struct ListResponse<T: Decodable>: Decodable {
        let sessions: [T]?
    }

    private static func list<T: Decodable>(_ path: String) async -> [T]? {
        guard let request = ServerConfig.shared.request(path, timeout: 12) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                print("[Sessions] \(path) -> HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            return try JSONDecoder().decode(ListResponse<T>.self, from: data).sessions ?? []
        } catch {
            // An older house without the endpoint: the list falls back to the
            // other source rather than showing an error.
            print("[Sessions] \(path) failed: \(error.localizedDescription)")
            return nil
        }
    }
}
