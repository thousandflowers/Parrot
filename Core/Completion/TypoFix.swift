import AppKit

/// Detects a misspelling in the word immediately before the caret and proposes a correction,
/// using the on-device `NSSpellChecker` (fast, multilingual, no model). Used so Tab can fix a
/// typo in the just-typed word instead of (or before) completing.
@MainActor
enum TypoFix {
    struct Fix: Equatable { let wrong: String; let correction: String }

    /// Returns a correction for the last word of `preContext`, or nil if it's correct / too short.
    static func check(preContext: String, language: String) -> Fix? {
        // The trailing run of letters before the caret = the word being / just typed.
        let trailing = preContext.reversed().prefix { $0.isLetter }
        let word = String(trailing.reversed())
        guard word.count >= 3 else { return nil }

        let checker = NSSpellChecker.shared
        // Spell-check against the language actually being written, not the fixed preference: using
        // the preference flags foreign words (English "very" as an Italian typo → "vero"). Detect
        // from the surrounding text; fall back to the preference when detection is unavailable.
        let detected = NSLinguisticTagger.dominantLanguage(for: preContext)
        let candidate = detected.flatMap { checker.availableLanguages.contains($0) ? $0 : nil } ?? language
        let lang = checker.availableLanguages.contains(candidate) ? candidate
            : (candidate.hasPrefix("en") ? "en" : candidate)
        let range = checker.checkSpelling(of: word, startingAt: 0, language: lang,
                                          wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        // Misspelled only if the whole word is flagged.
        guard range.location == 0, range.length == (word as NSString).length else { return nil }

        let guesses = checker.guesses(forWordRange: NSRange(location: 0, length: (word as NSString).length),
                                      in: word, language: lang, inSpellDocumentWithTag: 0) ?? []
        guard let best = guesses.first, best.caseInsensitiveCompare(word) != .orderedSame else { return nil }
        return Fix(wrong: word, correction: best)
    }
}
