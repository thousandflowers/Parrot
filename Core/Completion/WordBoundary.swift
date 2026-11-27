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

    /// True when gluing `continuation` directly onto `trailingWord` (no space) forms a single valid
    /// word. Disambiguates the letter-boundary spacing the model omits:
    ///   "se" + "ccavo" = "seccavo" (valid)   → continue the token, no space
    ///   "per" + "chiedere" = "perchiedere" (invalid) → new word, insert a space
    /// nonisolated so the pure postprocessor can call it; NSSpellChecker is safe off the main thread.
    /// `context` = the text the user is writing: its language picks the dictionary. Guessing the
    /// language from the glued token alone is noise ("Eugenioand" → Romanian) and sends the check to
    /// a dictionary that may not even be loaded.
    nonisolated static func continuationFormsWord(trailingWord: String, continuation: String, context: String = "") -> Bool {
        let combined = trailingWord + continuation
        guard combined.count >= 3, trailingWord.count >= 1, continuation.count >= 1 else { return false }
        let checker = NSSpellChecker.shared
        // A real word in ANY language the user writes in counts: the context's language when there
        // is enough text to detect it, plus the user's preferred languages. Never guess from the
        // glued token itself ("Eugenioand" → Romanian) or from a fragment too short to detect.
        let available = Set(checker.availableLanguages)
        let languages = candidateLanguages(context: context, preferred: Locale.preferredLanguages)
            .filter { available.contains($0) }
        return (languages.isEmpty ? ["en"] : languages).contains { lang in
            checker.checkSpelling(of: combined, startingAt: 0, language: lang,
                                  wrap: false, inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
        }
    }

    /// Detected context language first (only from text long enough to be reliable), then the
    /// user's preferred languages as primary subtags ("it-IT" → "it"), without duplicates.
    nonisolated static func candidateLanguages(context: String, preferred: [String]) -> [String] {
        let detected = context.count >= LanguageDetector.longTextMinLength
            ? NSLinguisticTagger.dominantLanguage(for: context).map { [$0] } ?? []
            : []
        let primaries = preferred.compactMap { $0.split(separator: "-").first.map(String.init) }
        return (detected + primaries).reduce(into: [String]()) { acc, lang in
            if !acc.contains(lang) { acc.append(lang) }
        }
    }
}
