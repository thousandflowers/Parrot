import Foundation

/// Turns onboarding tone input into personalization. Pure orchestration over the existing
/// `CorpusLearner` (extracts context→continuation pairs) and `CompletionLearningStore`
/// (`seed` for instant completions, `recordStyleSample` for the StyleProfile fingerprint).
enum ToneSeeder {
    struct Result: Sendable { let seededCount: Int }

    /// Learns from completed example phrases and/or pasted text.
    static func learn(
        phraseCompletions: [(opener: String, continuation: String)],
        pastedText: String?,
        store: CompletionLearningStore = .shared
    ) async -> Result {
        var corpus = ""
        for p in phraseCompletions {
            let cont = p.continuation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cont.isEmpty else { continue }
            let opener = p.opener.trimmingCharacters(in: .whitespacesAndNewlines)
            let sentence = opener.isEmpty ? cont : opener + " " + cont
            corpus += sentence + "\n"
        }
        if let pasted = pastedText?.trimmingCharacters(in: .whitespacesAndNewlines), !pasted.isEmpty {
            corpus += pasted + "\n"
        }
        let trimmed = corpus.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Result(seededCount: 0) }

        let entries = CorpusLearner.extract(from: corpus)
        let seeded = await store.seed(entries)
        await store.recordStyleSample(from: corpus)
        return Result(seededCount: seeded)
    }

    /// Learns from files/folders (upload). Reuses the same .txt/.md walk.
    static func learn(fromFiles urls: [URL], store: CompletionLearningStore = .shared) async -> Result {
        var corpus = ""
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let e = fm.enumerator(at: url, includingPropertiesForKeys: nil)
                while let f = e?.nextObject() as? URL {
                    if ["txt", "md", "markdown", "text"].contains(f.pathExtension.lowercased()),
                       let s = try? String(contentsOf: f, encoding: .utf8) { corpus += s + "\n" }
                }
            } else if let s = try? String(contentsOf: url, encoding: .utf8) {
                corpus += s + "\n"
            }
        }
        guard !corpus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return Result(seededCount: 0) }
        let entries = CorpusLearner.extract(from: corpus)
        let seeded = await store.seed(entries)
        await store.recordStyleSample(from: corpus)
        return Result(seededCount: seeded)
    }
}
