//
//  TranscriptStore.swift
//  Hearth
//
//  Per-persona transcripts that survive a relaunch. Desktop keeps these in
//  localStorage under hearth_msgs_<persona>; a phone gets JSON files in
//  Application Support, because transcripts are unbounded and UserDefaults
//  is not the place for something unbounded.
//
//  Only real turns are kept. System rows ("Connected to Hearth Server",
//  error copy) are the live session's narration -- replaying yesterday's
//  connection notices into today's feed would be noise presented as history.
//

import Foundation

@MainActor
public final class TranscriptStore {
    public init() {}

    /// Serializes writes and debounces the write-through: `messages` changes
    /// several times per turn, and the transcript only needs to be durable,
    /// not synchronous.
    private var pendingSave: Task<Void, Never>?

    // MARK: - Public API

    public func load(persona: String?) -> [ChatMessage] {
        guard let url = Self.fileURL(persona: persona),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ChatMessage].self, from: data)) ?? []
    }

    /// Debounced write of the feed's real turns under this persona's file.
    public func scheduleSave(_ messages: [ChatMessage], persona: String?) {
        let kept = messages.filter { $0.type != .system }
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            Self.write(kept, persona: persona)
        }
    }

    /// Remove one persona's transcript (Settings > clear history).
    public func clear(persona: String?) {
        pendingSave?.cancel()
        guard let url = Self.fileURL(persona: persona) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Remove every stored transcript.
    public func clearAll() {
        pendingSave?.cancel()
        guard let dir = Self.directory() else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Files

    private static func write(_ messages: [ChatMessage], persona: String?) {
        guard let url = fileURL(persona: persona) else { return }
        if messages.isEmpty {
            // An empty feed (session filed, history cleared) removes the
            // file rather than leaving "[]" litter behind.
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(messages) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func directory() -> URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        let dir = base.appendingPathComponent("HearthTranscripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(persona: String?) -> URL? {
        let name = persona?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        // A persona NAME becomes a FILE name; keep only what cannot escape
        // the directory or upset the filesystem.
        let safe = name.isEmpty
            ? "__default__"
            : String(name.unicodeScalars.filter {
                CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
            })
        return directory()?.appendingPathComponent("\(safe.isEmpty ? "__default__" : safe).json")
    }
}
