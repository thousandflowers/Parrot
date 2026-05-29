import Foundation
import OSLog

/// On-device learning for completion — inspired by (and going beyond) Cotypist's core. Records what
/// you accept and serves it INSTANTLY on a matching context (no model call). Improvements over a
/// plain exact-key store:
///  - **Variable-order n-gram keys** (last 1/2/3 words): a completion learned after "ti scrivo per"
///    still fires after "caro luca, ti scrivo per" via the shorter key — far more instant hits.
///  - **Acceptance-rate suppression**: a learned suggestion shown often but rarely accepted is
///    dropped, so the model isn't nagged with stale guesses.
/// Persisted as small JSON in the shared Application Support dir; cheap in RAM.
actor CompletionLearningStore {
    static let shared = CompletionLearningStore()

    private struct Entry: Codable { var text: String; var accepts: Int; var shows: Int; var lastUsed: Double }
    private var map: [String: Entry] = [:]
    private var loaded = false
    private let maxEntries = 4000
    private let minAccepts = 2          // confidence threshold to suggest
    private let suppressShows = 6       // after this many shows, require ≥20% acceptance to keep suggesting

    private static var fileURL: URL {
        let dir = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("Parrot")
        return dir.appendingPathComponent("completion_learned.json")
    }

    /// Variable-order keys for a context: last 3, 2, and 1 words (lowercased), longest first.
    nonisolated static func keys(forContext preContext: String) -> [String] {
        let words = preContext
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { $0.lowercased() }
        guard !words.isEmpty else { return [] }
        var result: [String] = []
        for n in [3, 2, 1] where words.count >= n {
            result.append(words.suffix(n).joined(separator: " "))
        }
        return result   // longest → shortest
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        map = decoded
    }

    /// Records an accepted completion under every order key so varied future contexts match.
    func record(keys: [String], accepted: String) {
        let text = accepted
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !keys.isEmpty else { return }
        loadIfNeeded()
        let now = Date().timeIntervalSince1970
        for k in keys {
            if var e = map[k], e.text == text {
                e.accepts += 1; e.lastUsed = now; map[k] = e
            } else {
                map[k] = Entry(text: text, accepts: 1, shows: map[k]?.shows ?? 0, lastUsed: now)
            }
        }
        if map.count > maxEntries { evictOldest() }
        save()
    }

    /// Note that a learned suggestion was shown (for acceptance-rate suppression).
    func noteShown(key: String) {
        guard !key.isEmpty else { return }
        loadIfNeeded()
        guard var e = map[key] else { return }
        e.shows += 1
        map[key] = e
        save()
    }

    /// Best learned completion for the context (tries longest key first), or nil.
    /// Returns the matched key too, so the caller can attribute the "shown" event.
    func learnedSuggestion(keys: [String]) -> (text: String, key: String)? {
        loadIfNeeded()
        for k in keys {
            guard let e = map[k], e.accepts >= minAccepts else { continue }
            // Acceptance-rate suppression: shown a lot but rarely accepted (<20%) → skip.
            if e.shows >= suppressShows && e.accepts * 5 < e.shows { continue }
            return (e.text, k)
        }
        return nil
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
