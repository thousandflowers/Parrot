import Foundation

/// Per-sentence language detection for code-switching writers (e.g. Italian prose with
/// English technical phrases). The completion language should follow the sentence being
/// typed, not the app-level preference: "Devo chiamare il cliente because the deadline is"
/// must complete in English even though the field/session started in Italian.
enum SentenceLanguage {
    /// Words needed before the trailing slice is trusted; below this the detector would
    /// guess on 1-2 words — the exact short-prefix drift hazard — so we fall back.
    private static let minWords = 3
    /// When the current sentence fragment is too short, widen to this many trailing words
    /// so a mid-sentence switch ("… il cliente because the project deadline is") still
    /// lets the most recent words dominate the detection.
    private static let trailingWindow = 12

    private static let sentenceTerminators = CharacterSet(charactersIn: ".!?…;\n")

    /// Returns the two-letter code for the language of the sentence currently being
    /// typed, or `fallback` when there isn't enough signal.
    static func detect(preContext: String, fallback: String) -> String {
        let trimmed = preContext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }

        // Slice after the last sentence terminator = the sentence in progress.
        var slice = trimmed
        if let lastTerminator = trimmed.rangeOfCharacter(from: sentenceTerminators, options: .backwards) {
            slice = String(trimmed[lastTerminator.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let words = slice.split(whereSeparator: { $0.isWhitespace })
        if words.count < minWords {
            // Sentence just started — widen to the trailing window across the boundary.
            let allWords = trimmed.split(whereSeparator: { $0.isWhitespace })
            guard allWords.count >= minWords else { return fallback }
            slice = allWords.suffix(trailingWindow).joined(separator: " ")
            return LanguageDetector.detect(text: slice, fallbackLanguage: fallback)
        }

        // The words nearest the caret decide: a mid-sentence switch ("Devo chiamare il
        // cliente because the project deadline is") must complete in the tail language
        // even when the sentence as a whole leans the other way. The full-sentence
        // detection only breaks ties when the short tail is ambiguous.
        let sentenceLang = LanguageDetector.detect(text: slice, fallbackLanguage: fallback)
        let tail = words.suffix(4).joined(separator: " ")
        return LanguageDetector.detect(text: tail, fallbackLanguage: sentenceLang)
    }
}
