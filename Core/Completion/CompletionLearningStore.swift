import Foundation
import OSLog

/// Lightweight on-device learning for completion — inspired by Cotypist's core (which persists
/// what you accept and adapts). When you accept a completion, the (context → completion) pair is
/// stored with a frequency count. On the next matching context, Wren can suggest it INSTANTLY —
/// no model call — so your recurring phrases are fast and personal. Persisted as small JSON in the
/// shared Application Support dir; trivially cheap in RAM.
actor CompletionLearningStore {
    static let shared = CompletionLearningStore()

    private struct Entry: Codable { var text: String; var count: Int; var lastUsed: Double }
    private var map: [String: Entry] = [:]   // contextKey -> best accepted completion
    private var loaded = false
    private let maxEntries = 2000

    private static var fileURL: URL {
        let dir = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("Parrot")
        return dir.appendingPathComponent("completion_learned.json")
    }

    /// Normalized key from the tail of the user's text: the last up-to-3 words, lowercased.
    nonisolated static func key(forContext preContext: String) -> String? {
        let words = preContext
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .suffix(3)
            .map { $0.lowercased() }
        guard words.count >= 2 else { return nil }   // need a little context to be meaningful
        return words.joined(separator: " ")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        map = decoded
    }

    /// Records an accepted completion for a context.
    func record(contextKey: String, accepted: String) {
        let text = accepted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !contextKey.isEmpty else { return }
        loadIfNeeded()
        if var e = map[contextKey], e.text == accepted {
            e.count += 1; e.lastUsed = Date().timeIntervalSince1970; map[contextKey] = e
        } else {
            // New or changed completion for this context — keep the most recent acceptance.
            map[contextKey] = Entry(text: accepted, count: 1, lastUsed: Date().timeIntervalSince1970)
        }
        if map.count > maxEntries { evictOldest() }
        save()
    }

    /// Returns a learned completion for the context, if one was accepted ≥2 times (confident).
    func learnedSuggestion(contextKey: String) -> String? {
        loadIfNeeded()
        guard let e = map[contextKey], e.count >= 2 else { return nil }
        return e.text
    }

    private func evictOldest() {
        let sorted = map.sorted { $0.value.lastUsed < $1.value.lastUsed }
        for (k, _) in sorted.prefix(map.count - maxEntries) { map.removeValue(forKey: k) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
