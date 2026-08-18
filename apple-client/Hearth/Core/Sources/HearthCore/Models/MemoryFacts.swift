//
//  MemoryFacts.swift
//  HearthCore
//
//  What the house has come to know about you, as the desktop rail shows it.
//
//  One route, `/journal/facts`, whose body is markdown: bullets are facts and
//  headings are not. That parse is the desktop's `MemoryTab`, and the phone
//  already does a near-identical one inside `JournalLibrary.livingVolumes` to
//  build the "About Joshua" volume -- the difference is what each wants back.
//  The library wants a book of entries; a rail wants the lines.
//
//  Kept honest about failure, because this file's ancestor was not: the desktop
//  tab showed two invented sentences with fabricated attribution until
//  2026-08-05. Nothing here fabricates. An unreachable house says so, an empty
//  file says so, and neither is dressed up as a memory.
//

import Foundation

/// One remembered thing.
public struct MemoryFact: Identifiable, Hashable, Sendable {
    /// The date the house stamped it, when there is one.
    public let date: String
    /// The fact itself, tags and stamp stripped.
    public let text: String
    public var id: String { date + "|" + text }
}

@MainActor
public final class MemoryFactsLoader: ObservableObject {
    public init() {}

    @Published public private(set) var facts: [MemoryFact] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var hasLoaded = false
    /// The house answered with something other than facts, or not at all.
    @Published public private(set) var unreachable = false

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }

        guard let url = ServerConfig.shared.url("/journal/facts") else {
            unreachable = true
            return
        }
        var request = URLRequest(url: url)
        ServerConfig.shared.authorize(&request)
        request.timeoutInterval = 8
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                print("[Memory] /journal/facts -> HTTP \(code)")
                unreachable = true
                return
            }
            let body = try JSONDecoder().decode(FactsBody.self, from: data).body
            facts = Self.parse(body)
            unreachable = false
        } catch {
            print("[Memory] /journal/facts failed: \(error.localizedDescription)")
            unreachable = true
        }
    }

    private struct FactsBody: Decodable {
        var body: String = ""
    }

    /// Bullets are facts; everything else is structure.
    ///
    /// A line looks like `- [2026-05-28] [tag] the fact itself`, and both
    /// bracketed prefixes are optional -- an older house wrote plain bullets.
    /// So the stamp is READ when present rather than required, and a line that
    /// carries none still becomes a fact instead of being dropped.
    static func parse(_ body: String) -> [MemoryFact] {
        body.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
            var rest = line.dropFirst(2).trimmingCharacters(in: .whitespaces)

            var date = ""
            // The first bracket is the stamp, the rest are tags. Tags are for
            // the house's own retrieval and say nothing to a person reading
            // them, so they come off.
            while rest.hasPrefix("["), let end = rest.firstIndex(of: "]") {
                let inner = String(rest[rest.index(after: rest.startIndex)..<end])
                // Recognised by SHAPE, not by position: a bracket only becomes
                // a stamp if it reads as one. A house that writes tags and no
                // date would otherwise print "[project]" where the date goes.
                if date.isEmpty, Self.looksLikeADate(inner) { date = inner }
                rest = String(rest[rest.index(after: end)...])
                    .trimmingCharacters(in: .whitespaces)
            }

            guard !rest.isEmpty else { return nil }
            return MemoryFact(date: date, text: rest)
        }
    }

    /// `2026-05-28`, and nothing looser.
    private static func looksLikeADate(_ s: String) -> Bool {
        let parts = s.split(separator: "-")
        guard parts.count == 3 else { return false }
        return parts[0].count == 4 && parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }
}
