import Foundation
import OSLog

/// Fingerprint of the user's writing style, built from accepted completions.
/// Used to steer the model toward the user's natural voice via prompt injection.
struct StyleProfile: Codable, Sendable {
    var totalSentences: Int = 0
    var totalWords: Int = 0
    var totalChars: Int = 0
    var contractions: Int = 0        // "don't", "it's", "I'm" etc.
    var uniqueWords: Set<String> = []

    /// Average words per sentence (or 0 if no data).
    var avgSentenceLength: Double {
        guard totalSentences > 0 else { return 0 }
        return Double(totalWords) / Double(totalSentences)
    }

    /// Unique / total word ratio — higher = richer vocabulary.
    var vocabDiversity: Double {
        guard totalWords > 0 else { return 0 }
        return Double(uniqueWords.count) / Double(totalWords)
    }

    /// How often the user contracts (0…1). Lower = more formal.
    var contractionRate: Double {
        guard totalWords > 0 else { return 0 }
        return Double(contractions) / Double(totalWords)
    }

    /// Human-readable descriptor injected into the model prompt.
    /// Stays ~2 lines so it's a lightweight hint, not a dominating instruction.
    var descriptor: String {
        guard totalSentences >= 3 else { return "" }
        let formality: String
        if contractionRate > 0.08 { formality = "casual, conversational" }
        else if contractionRate > 0.03 { formality = "neutral" }
        else { formality = "formal, polished" }
        let vocab: String
        if vocabDiversity > 0.6 { vocab = "rich, varied vocabulary" }
        else if vocabDiversity > 0.35 { vocab = "balanced vocabulary" }
        else { vocab = "concise, direct" }
        let sentence: String
        if avgSentenceLength > 20 { sentence = "long, detailed sentences" }
        else if avgSentenceLength > 12 { sentence = "moderate-length sentences" }
        else { sentence = "short, punchy sentences" }
        return "User tends to write in a \(formality) style with \(vocab) and \(sentence)."
    }

    mutating func update(from text: String) {
        let words = text.split(separator: " ").map(String.init)
        totalWords += words.count
        totalChars += text.count
        for w in words { uniqueWords.insert(w.lowercased()) }
        // Sentence count via sentence terminators
        totalSentences += text.filter { $0 == "." || $0 == "!" || $0 == "?" }.count
        if totalSentences == 0, !text.isEmpty { totalSentences = 1 }
        // Contraction detection
        let lower = text.lowercased()
        let contractionPatterns = ["'t ", "'s ", "'m ", "'re ", "'ve ", "'ll ", "'d ", "n't "]
        for pat in contractionPatterns {
            var search = lower.startIndex
            while let r = lower[search...].range(of: pat) {
                contractions += 1
                search = r.upperBound
            }
        }
    }
}

/// On-device learning for completion — inspired by (and going beyond) Cotypist's core. Records what
/// you accept and serves it INSTANTLY on a matching context (no model call). Improvements over a
/// plain exact-key store:
///  - **Variable-order n-gram keys** (last 1/2/3 words): a completion learned after "ti scrivo per"
///    still fires after "caro luca, ti scrivo per" via the shorter key — far more instant hits.
///  - **Acceptance-rate suppression**: a learned suggestion shown often but rarely accepted is
///    dropped, so the model isn't nagged with stale guesses.
///  - **StyleProfile**: builds a writing fingerprint from accepted completions.
/// Persisted as small JSON in the shared Application Support dir; cheap in RAM.
actor CompletionLearningStore {
    static let shared = CompletionLearningStore()

    /// When `false` the instance never reads from or writes to disk — used by tests
    /// to avoid polluting or being contaminated by the shared on-disk state.
    private let loadsFromDisk: Bool

    init(loadsFromDisk: Bool = true) {
        self.loadsFromDisk = loadsFromDisk
    }

    private struct Entry: Codable { var text: String; var accepts: Int; var shows: Int; var lastUsed: Double }
    private var map: [String: Entry] = [:]
    private var loaded = false
    private let maxEntries = 4000
    private let minAccepts = 2          // confidence threshold to suggest
    private let suppressShows = 6       // after this many shows, require ≥20% acceptance to keep suggesting

    /// Accumulated writing fingerprint from accepted completions.
    private var profile = StyleProfile()

    private static var fileURL: URL {
        let dir = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("Parrot")
        return dir.appendingPathComponent("completion_learned.json")
    }

    /// Variable-order keys for a context: last 3, 2, and 1 words (lowercased), longest first.
    /// Single-word (1-gram) keys must be at least 3 characters to avoid matching completely
    /// unrelated contexts on generic function words ("a", "di", "il", "per", "in", etc.).
    nonisolated static func keys(forContext preContext: String) -> [String] {
        let words = preContext
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { $0.lowercased() }
        guard !words.isEmpty else { return [] }
        var result: [String] = []
        for n in [3, 2, 1] where words.count >= n {
            // Skip 1-gram keys for very short words (function words match too broadly).
            if n == 1, words.last!.count < 3 { continue }
            result.append(words.suffix(n).joined(separator: " "))
        }
        return result   // longest → shortest
    }

    /// Return the accumulated writing fingerprint as a prompt fragment, or empty if insufficient data.
    func styleDescriptor() -> String {
        profile.descriptor
    }

    private struct PersistedRoot: Codable {
        var map: [String: Entry]
        var profile: StyleProfile
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard loadsFromDisk else { return }
        guard let data = try? Data(contentsOf: Self.fileURL) else { return }
        if let root = try? JSONDecoder().decode(PersistedRoot.self, from: data) {
            map = root.map
            profile = root.profile
        } else if let legacy = try? JSONDecoder().decode([String: Entry].self, from: data) {
            map = legacy
        }
    }

    /// Records an accepted completion under every order key so varied future contexts match.
    func record(keys: [String], accepted: String) {
        let text = accepted
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !keys.isEmpty else { return }
        loadIfNeeded()
        let now = Date().timeIntervalSince1970
        // Single-slot LFU per key. A different completion competing for the same key must NOT reset
        // the count to 1 — that starved both candidates so neither reached `minAccepts` and learning
        // never fired for varied contexts. Decrement the incumbent instead; the challenger only takes
        // the slot once the incumbent loses, so the dominant phrase accrues accepts and gets served.
        for k in keys {
            if var e = map[k] {
                if e.text == text {
                    e.accepts += 1
                    e.lastUsed = now
                } else {
                    e.accepts -= 1
                    if e.accepts <= 0 {
                        e = Entry(text: text, accepts: 1, shows: 0, lastUsed: now)
                    }
                }
                map[k] = e
            } else {
                map[k] = Entry(text: text, accepts: 1, shows: 0, lastUsed: now)
            }
        }
        profile.update(from: accepted)
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

    /// Best learned completion across keys, with degressive key-length priority.
    /// Longer keys (more specific context) are preferred over shorter ones:
    /// 3-gram beats 2-gram beats 1-gram. Within the same key length, picks the
    /// highest acceptance rate. This prevents single-word keys from overriding
    /// multi-word matches. Returns the matched key so the caller can attribute
    /// the "shown" event.
    func learnedSuggestion(keys: [String]) -> (text: String, key: String)? {
        loadIfNeeded()
        var bestByOrder: [Int: (text: String, key: String, score: Double)] = [:]
        for k in keys {
            guard let e = map[k], e.accepts >= minAccepts else { continue }
            if e.shows >= suppressShows && e.accepts * 5 < e.shows { continue }
            let order = k.split(separator: " ").count
            let score = Double(e.accepts) / max(1, Double(e.shows + 1))
            if let (_, _, prev) = bestByOrder[order], prev >= score { continue }
            bestByOrder[order] = (e.text, k, score)
        }
        for n in [3, 2, 1] {
            if let b = bestByOrder[n] { return (b.text, b.key) }
        }
        return nil
    }

    /// Seeds learned entries (e.g. from the user's own writing) as already-confident.
    @discardableResult
    func seed(_ entries: [(key: String, text: String)], accepts: Int = 2) -> Int {
        loadIfNeeded()
        let now = Date().timeIntervalSince1970
        var added = 0
        for e in entries {
            guard !e.key.isEmpty, !e.text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if var x = map[e.key], x.text == e.text {
                x.accepts = max(x.accepts, accepts); map[e.key] = x
            } else if map[e.key] == nil {
                map[e.key] = Entry(text: e.text, accepts: accepts, shows: 0, lastUsed: now); added += 1
            }
        }
        if map.count > maxEntries { evictOldest() }
        save()
        return added
    }

    private func evictOldest() {
        let sorted = map.sorted { $0.value.lastUsed < $1.value.lastUsed }
        for (k, _) in sorted.prefix(map.count - maxEntries) { map.removeValue(forKey: k) }
    }

    private func save() {
        guard loadsFromDisk else { return }
        let root = PersistedRoot(map: map, profile: profile)
        guard let data = try? JSONEncoder().encode(root) else { return }
        try? FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    /// Updates the writing-style fingerprint from a raw sample (e.g. onboarding phrase
    /// completions or pasted text). Unlike `seed`, this feeds `StyleProfile` so
    /// `styleDescriptor()` can populate. No-op for blank text.
    func recordStyleSample(from text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        loadIfNeeded()
        profile.update(from: text)
        save()
    }
}
