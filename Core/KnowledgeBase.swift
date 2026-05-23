import Foundation

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
        let dir = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Parrot")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("knowledge.json")
    }

    private init() {
        let url = Self.fileURL
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([KnowledgeDocument].self, from: data) {
            documents = decoded
        }
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
        guard !documents.isEmpty else { return nil }

        let relevant = documents
            .filter { doc in
                let words = doc.content.split(separator: " ").map { $0.lowercased() }
                let textWords = Set(text.split(separator: " ").map { $0.lowercased() })
                return words.contains { textWords.contains($0) }
            }
            .sorted { a, b in
                a.source == .file ? true : b.source == .file ? false : a.source == .snippet
            }

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
        guard original != corrected else { return }
        let diff = original.split(separator: " ").enumerated()
            .filter { i, word in
                let corrWords = corrected.split(separator: " ")
                return i < corrWords.count && word.lowercased() != corrWords[i].lowercased()
            }
            .map { _, word in String(word) }

        guard !diff.isEmpty else { return }

        let existing = documents.first { doc in
            doc.source == .autoLearned && doc.content.contains(diff.first ?? "")
        }

        if let existing {
            var updated = existing
            updated.content += "\n" + corrected
            updateDocument(updated)
        } else {
            addDocument(
                title: "Pattern: \(diff.prefix(3).joined(separator: " → "))",
                content: "Original: \(original)\nCorrected: \(corrected)",
                source: .autoLearned
            )
        }
    }

    private func save() {
        try? JSONEncoder().encode(documents).write(to: Self.fileURL, options: .atomic)
    }
}
