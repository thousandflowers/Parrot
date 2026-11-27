import Foundation
import OSLog

struct KnowledgeDocument: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var title: String
    var content: String
    var source: Source
    var createdAt: Date

    enum Source: String, Codable, Sendable {
        case file = "file"
        case snippet = "snippet"
        case autoLearned = "auto_learned"
    }
}

actor KnowledgeBase {
    static let shared = KnowledgeBase()
    private var documents: [KnowledgeDocument] = []

    private nonisolated static var fileURL: URL {
        let dir = (AppPaths.applicationSupport ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Parrot")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("knowledge.json")
    }

    private init() {
        documents = PersistentJSON.load([KnowledgeDocument].self, from: Self.fileURL) ?? []
    }

    var allDocuments: [KnowledgeDocument] { documents }

    func addDocument(title: String, content: String, source: KnowledgeDocument.Source) {
        let doc = KnowledgeDocument(id: UUID(), title: title, content: content, source: source, createdAt: Date())
        documents.append(doc)
        save()
    }

    func removeDocument(id: UUID) {
        documents.removeAll { $0.id == id }
        save()
    }

    func updateDocument(_ doc: KnowledgeDocument) {
        if let idx = documents.firstIndex(where: { $0.id == doc.id }) {
            documents[idx] = doc
            save()
        }
    }

    func contextForPrompt(text: String, maxTokens: Int = 500) -> String? {
        let relevant = Self.relevantDocuments(documents, for: text)
        guard !relevant.isEmpty else { return nil }

        let combined = relevant
            .map { "\($0.title):\n\($0.content.prefix(500))" }
            .joined(separator: "\n\n")
            .prefix(maxTokens * 4)

        return """
        REFERENCE CONTEXT:
        \(combined)
        Use this reference material to inform your corrections.
        """
    }

    func learnFromCorrection(original: String, corrected: String) {
        let updated = Self.learning(from: documents, original: original, corrected: corrected)
        guard updated != documents else { return }
        documents = updated
        save()
    }

    private func save() {
        let count = documents.count
        do {
            try JSONEncoder().encode(documents).write(to: Self.fileURL, options: .atomic)
        } catch {
            Logger.core.error("KnowledgeBase: save failed (\(count, privacy: .public) docs): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Pure logic (testable)

    /// Lower-cased alphanumeric tokens long enough to carry meaning. Length, not a stop-word
    /// list, filters out function words ("the", "and", "per", "che") in any language.
    nonisolated static func terms(in text: String) -> Set<String> {
        Set(text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= Constants.knowledgeMinTermLength })
    }

    /// Documents sharing enough meaningful terms with `text`, best source first, then most overlap.
    /// A short text with a single meaningful term needs only that one term to match.
    nonisolated static func relevantDocuments(_ docs: [KnowledgeDocument], for text: String) -> [KnowledgeDocument] {
        let textTerms = terms(in: text)
        guard !textTerms.isEmpty else { return [] }
        let required = min(Constants.knowledgeMinSharedTerms, textTerms.count)
        return docs
            .map { (doc: $0, overlap: terms(in: $0.content).intersection(textTerms).count) }
            .filter { $0.overlap >= required }
            .sorted { a, b in
                let lhs = priority(a.doc.source), rhs = priority(b.doc.source)
                return lhs != rhs ? lhs > rhs : a.overlap > b.overlap
            }
            .map(\.doc)
    }

    /// Returns `docs` with the correction recorded: appended to the auto-learned doc for the
    /// exact same word pattern, or as a new doc. Each doc is capped (oldest examples dropped).
    nonisolated static func learning(from docs: [KnowledgeDocument], original: String, corrected: String,
                                     now: Date = Date()) -> [KnowledgeDocument] {
        guard original != corrected else { return docs }
        let correctedWords = corrected.split(separator: " ")
        let changes = original.split(separator: " ").enumerated()
            .filter { i, word in i < correctedWords.count && word.lowercased() != correctedWords[i].lowercased() }
            .map { i, word in "\(word.lowercased())→\(correctedWords[i].lowercased())" }
        guard !changes.isEmpty else { return docs }

        let title = "Pattern: \(changes.prefix(3).joined(separator: ", "))"
        guard let index = docs.firstIndex(where: { $0.source == .autoLearned && $0.title == title }) else {
            let content = capped("Original: \(original)\nCorrected: \(corrected)")
            return docs + [KnowledgeDocument(id: UUID(), title: title, content: content, source: .autoLearned, createdAt: now)]
        }
        let existing = docs[index]
        let lines = existing.content.split(separator: "\n", omittingEmptySubsequences: true)
        guard !lines.contains(Substring(corrected)) else { return docs }
        var updated = existing
        updated.content = capped(existing.content + "\n" + corrected)
        return docs.enumerated().map { $0.offset == index ? updated : $0.element }
    }

    /// Keeps the newest whole lines within `Constants.knowledgeAutoLearnedMaxChars`.
    private nonisolated static func capped(_ content: String) -> String {
        let limit = Constants.knowledgeAutoLearnedMaxChars
        guard content.count > limit else { return content }
        var kept: [Substring] = []
        var total = 0
        for line in content.split(separator: "\n").reversed() {
            let cost = line.count + (kept.isEmpty ? 0 : 1)
            guard total + cost <= limit else { break }
            kept.append(line)
            total += cost
        }
        return kept.reversed().joined(separator: "\n")
    }

    private nonisolated static func priority(_ source: KnowledgeDocument.Source) -> Int {
        switch source {
        case .file: 3
        case .snippet: 2
        case .autoLearned: 1
        }
    }
}
