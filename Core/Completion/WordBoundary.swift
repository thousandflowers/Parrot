import AppKit

/// Decides whether the caret sits inside a partial word, so a completion should CONTINUE that word
/// ("rece" → "ption") rather than start a new one ("per" → " chiedere"). Uses the on-device spell
/// checker: a trailing run of letters that is not a complete dictionary word is treated as mid-word.
@MainActor
enum WordBoundary {
    static func isMidWord(preContext: String) -> Bool {
        let trailing = preContext.reversed().prefix { $0.isLetter }
        let word = String(trailing.reversed())
        guard !word.isEmpty else { return false }     // ends with space/punctuation → word boundary
        if word.count < 2 { return true }             // a lone letter is almost always a fragment

        let checker = NSSpellChecker.shared
        let detected = NSLinguisticTagger.dominantLanguage(for: preContext)
        let lang = detected.flatMap { checker.availableLanguages.contains($0) ? $0 : nil } ?? "en"
        let r = checker.checkSpelling(of: word, startingAt: 0, language: lang,
                                      wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        // The whole trailing word is flagged as misspelled → it is an incomplete word → mid-word.
        return r.location == 0 && r.length == (word as NSString).length
    }

    /// Cheap boundary check: the caret is mid-word iff the char immediately before it is a letter.
    /// (Reliable and instant — unlike the spell-check `isMidWord`, which we no longer use for spacing.)
    nonisolated static func isMidWordFast(preContext: String) -> Bool {
        guard let last = preContext.last else { return false }
        return last.isLetter
    }
}
