import Foundation
import OSLog

/// Builds Wren's completion memory from the user's OWN writing (pasted text or a folder of files).
/// Extracts frequent "after these words, you usually write …" continuations and seeds them as
/// confident — instant personalization from day one, the clean alternative to copying another app's
/// opaque learned data.
enum CorpusLearner {
    /// Extracts frequent (context-key → continuation) pairs from text. Keys are lowercased 2- and
    /// 3-word suffixes (matching `CompletionLearningStore.keys`); continuations keep original case.
    static func extract(from text: String, minCount: Int = 2, maxEntries: Int = 3000) -> [(key: String, text: String)] {
        // Tokenize per line so continuations don't cross unrelated boundaries.
        var counts: [String: [String: Int]] = [:]   // key -> continuation -> count
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard words.count >= 3 else { continue }
            for i in 1..<words.count {
                let cont = " " + words[i..<min(i + 3, words.count)].joined(separator: " ")
                for n in [3, 2] where i >= n {
                    let key = words[(i - n)..<i].map { $0.lowercased() }.joined(separator: " ")
                    counts[key, default: [:]][cont, default: 0] += 1
                }
            }
        }
        // Keep, per key, the single most frequent continuation that occurs ≥ minCount.
        var out: [(key: String, text: String)] = []
        for (key, conts) in counts {
            guard let best = conts.max(by: { $0.value < $1.value }), best.value >= minCount else { continue }
            out.append((key, best.key))
            if out.count >= maxEntries { break }
        }
        return out
    }

    /// Learns from raw text; returns how many entries were seeded.
    static func learn(from text: String) async -> Int {
        let entries = extract(from: text)
        guard !entries.isEmpty else { return 0 }
        return await CompletionLearningStore.shared.seed(entries)
    }

    /// Learns from a folder/files of `.txt`/`.md` (recursively). Returns seeded count.
    static func learn(fromFiles urls: [URL]) async -> Int {
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
        return await learn(from: corpus)
    }
}
