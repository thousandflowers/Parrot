import Foundation

/// A user-defined text expansion: when the typed abbreviation matches, Tab replaces it with the expansion.
struct Snippet: Codable, Identifiable, Sendable {
    /// Immutable identity so Presets-like JSON storage works (id stays fixed across renames).
    let id: UUID
    var abbreviation: String
    var expansion: String
    var isEnabled: Bool

    init(id: UUID = UUID(), abbreviation: String, expansion: String, isEnabled: Bool = true) {
        self.id = id
        self.abbreviation = abbreviation
        self.expansion = expansion
        self.isEnabled = isEnabled
    }
}

/// Matches the last typed word against known snippet abbreviations.
enum SnippetMatcher {
    static func match(preContext: String, snippets: [Snippet]) -> Snippet? {
        let lastWord = preContext
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .last?
            .lowercased()
        guard let word = lastWord, !word.isEmpty else { return nil }
        return snippets.first { $0.isEnabled && $0.abbreviation.lowercased() == word }
    }
}
