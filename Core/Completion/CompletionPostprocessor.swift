import Foundation

/// Pure cleaning of a raw model continuation into a short inline suggestion.
/// No I/O, no state — fully unit-testable.
enum CompletionPostprocessor {
    /// Cleans `raw` into an inline suggestion, or returns nil if there is nothing useful to show.
    /// - `preContext`: the text before the caret, used to strip an echoed prefix.
    /// - `maxWords`: hard cap on suggestion length (a "short" completion budget).
    static func clean(raw: String, preContext: String, maxWords: Int) -> String? {
        var text = raw

        // 1. Some models echo the prompt/prefix back. Strip it if the output starts with it.
        if !preContext.isEmpty, text.hasPrefix(preContext) {
            text = String(text.dropFirst(preContext.count))
        }

        // 2. Short completions stop at the first line break — a new paragraph is not an inline hint.
        if let nl = text.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            text = String(text[..<nl])
        }

        // 3. Collapse to the word budget.
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return nil }
        var capped = words.prefix(max(1, maxWords)).joined(separator: " ")

        // 4. Deterministic join spacing — NEVER join two words. The model is unreliable at adding
        //    the boundary space, so we decide it here: if the user's text ends with a non-space
        //    character, the suggestion must start with exactly one space; if it already ends with
        //    whitespace, the suggestion must start with none.
        if let last = preContext.last, !last.isWhitespace {
            capped = " " + capped
        }
        text = capped

        // 5. A pure-whitespace result is useless.
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return nil }

        return text
    }
}
