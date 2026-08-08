//
//  JournalModels.swift
//  Hearth
//
//  Selene's Library, read-only. Mirrors Valar's `/journal/*` routes
//  (Valar/valar/gateway/journal.py), which parse the Engram junction directly.
//
//  The shelf endpoint covers PROJECT and LIFE books only. The three living
//  volumes -- The Journal, About Joshua, Selene's Ledger -- are not on it, so
//  the client assembles them from /sessions, /reviews and /facts and supplies
//  their keeper summaries locally until the server curates them. See the note
//  in tasks/hearth-ios-handoff.md.
//

import Foundation

// MARK: - Wire shapes

/// One entry inside a shelf book: title, date, synopsis (Valar's `t`/`d`/`s`).
struct JournalEntry: Decodable, Identifiable {
    let title: String
    let date: String
    let synopsis: String
    var persona: String = "Sulivan"

    var id: String { "\(date)-\(title)" }

    enum CodingKeys: String, CodingKey {
        case title = "t"
        case date = "d"
        case synopsis = "s"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decode(String.self, forKey: .title)) ?? "Untitled"
        date = (try? c.decode(String.self, forKey: .date)) ?? ""
        synopsis = (try? c.decode(String.self, forKey: .synopsis)) ?? ""
    }

    init(title: String, date: String, synopsis: String, persona: String) {
        self.title = title
        self.date = date
        self.synopsis = synopsis
        self.persona = persona
    }
}

struct JournalBook: Decodable, Identifiable {
    let title: String
    let pages: Int
    let summary: String
    var entries: [JournalEntry] = []
    /// Which room of the library this book stands in.
    var shelf: Shelf = .project

    var id: String { "\(shelf.rawValue)-\(title)" }

    enum Shelf: String { case heart, life, project, seedling }

    enum CodingKeys: String, CodingKey { case title, pages, summary, entries }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decode(String.self, forKey: .title)) ?? "Untitled"
        pages = (try? c.decode(Int.self, forKey: .pages)) ?? 0
        summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        entries = (try? c.decode([JournalEntry].self, forKey: .entries)) ?? []
    }

    init(title: String, pages: Int, summary: String, entries: [JournalEntry], shelf: Shelf) {
        self.title = title
        self.pages = pages
        self.summary = summary
        self.entries = entries
        self.shelf = shelf
    }

    /// Seedlings are the one-page projects; they stand under glass rather than
    /// cluttering the Forge shelf (tasks/journal-library-map.md).
    var isSeedling: Bool { pages <= 1 }
}

private struct ShelfResponse: Decodable {
    var projects: [JournalBook] = []
    var life: [JournalBook] = []
}

private struct SessionsResponse: Decodable {
    struct Session: Decodable {
        var title: String = ""
        var date: String = ""
        var persona: String = ""
        var summary: String = ""
    }
    var sessions: [Session] = []
}

private struct ReviewsResponse: Decodable {
    struct Review: Decodable {
        var date: String = ""
        var body: String = ""
    }
    var reviews: [Review] = []
}

private struct FactsResponse: Decodable {
    var body: String = ""
}

// MARK: - The library

@MainActor
final class JournalLibrary: ObservableObject {
    @Published private(set) var heart: [JournalBook] = []
    @Published private(set) var life: [JournalBook] = []
    @Published private(set) var projects: [JournalBook] = []
    @Published private(set) var seedlings: [JournalBook] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?

    var isEmpty: Bool { heart.isEmpty && life.isEmpty && projects.isEmpty && seedlings.isEmpty }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil

        // Four calls because the living volumes are not on /journal/shelf.
        async let shelf: ShelfResponse? = Self.get("/journal/shelf")
        async let sessions: SessionsResponse? = Self.get("/journal/sessions?limit=200")
        async let reviews: ReviewsResponse? = Self.get("/journal/reviews")
        async let facts: FactsResponse? = Self.get("/journal/facts")

        let (s, se, r, f) = await (shelf, sessions, reviews, facts)

        if let s {
            let allProjects = s.projects.map { book -> JournalBook in
                var b = book
                b.shelf = b.isSeedling ? .seedling : .project
                return b
            }
            projects = allProjects.filter { !$0.isSeedling }.sorted { $0.pages > $1.pages }
            seedlings = allProjects.filter(\.isSeedling)
            life = s.life.map { book in
                var b = book
                b.shelf = .life
                return b
            }
        }

        heart = Self.livingVolumes(sessions: se, reviews: r, facts: f)

        if s == nil && heart.isEmpty {
            loadError = ServerConfig.shared.isConfigured
                ? "Could not reach the library at \(ServerConfig.shared.address)."
                : "No house configured yet."
        }
        isLoading = false
    }

    /// The three volumes on the display shelf, assembled client-side.
    private static func livingVolumes(
        sessions: SessionsResponse?,
        reviews: ReviewsResponse?,
        facts: FactsResponse?
    ) -> [JournalBook] {
        var books: [JournalBook] = []

        if let sessions, !sessions.sessions.isEmpty {
            let entries = sessions.sessions
                .sorted { $0.date > $1.date }
                .map {
                    JournalEntry(
                        title: $0.title.isEmpty ? "Session" : $0.title,
                        date: $0.date,
                        synopsis: $0.summary,
                        persona: $0.persona.split(separator: " ").first.map(String.init) ?? "Sulivan"
                    )
                }
            books.append(JournalBook(
                title: "The Journal",
                pages: entries.count,
                summary: "The working record of what was built, decided and left open on each day. This volume and the Ledger are the two that grow almost daily.",
                entries: entries,
                shelf: .heart
            ))
        }

        if let facts, !facts.body.isEmpty {
            let lines = facts.body
                .split(separator: "\n")
                .map(String.init)
                .filter { $0.hasPrefix("- [") }
            let entries = lines.map { line -> JournalEntry in
                // "- [2026-05-28] [tag] the fact itself"
                let date = line.dropFirst(3).prefix { $0 != "]" }
                let text = line.drop { $0 != "]" }.dropFirst()
                return JournalEntry(
                    title: String(text.trimmingCharacters(in: .whitespaces).prefix(70)),
                    date: String(date),
                    synopsis: text.trimmingCharacters(in: .whitespaces),
                    persona: "Selene"
                )
            }
            books.append(JournalBook(
                title: "About Joshua",
                pages: entries.count,
                summary: "What the house knows about you, held as durable facts rather than transcript. One living page, refreshed rather than appended. Curation is conversational: ask Selene to forget something and she will.",
                entries: entries,
                shelf: .heart
            ))
        }

        if let reviews, !reviews.reviews.isEmpty {
            let entries = reviews.reviews
                .sorted { $0.date > $1.date }
                .map {
                    JournalEntry(
                        title: "Daily review",
                        date: $0.date,
                        synopsis: $0.body,
                        persona: "Selene"
                    )
                }
            books.append(JournalBook(
                title: "Selene's Ledger",
                pages: entries.count,
                summary: "Nightly consolidations. Each one reads the day and keeps what will still matter next month. Where the Journal records, the Ledger decides what endures.",
                entries: entries,
                shelf: .heart
            ))
        }

        return books
    }

    private static func get<T: Decodable>(_ path: String) async -> T? {
        guard let url = ServerConfig.shared.url(path) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                print("[Journal] \(path) -> HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("[Journal] \(path) failed: \(error.localizedDescription)")
            return nil
        }
    }
}
