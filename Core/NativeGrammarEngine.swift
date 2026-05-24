import AppKit
import Foundation

@MainActor
enum NativeGrammarEngine {
    private static func spellCheckerLocale(for language: String) -> String {
        let available = NSSpellChecker.shared.availableLanguages
        if available.contains(language) { return language }
        let primary = String(language.split(separator: "-").first ?? Substring(language))
        return available.first(where: { $0.hasPrefix(primary) }) ?? language
    }

    static func check(_ text: String, language: String) -> [CorrectionSpan] {
        let checker = NSSpellChecker.shared
        let locale = spellCheckerLocale(for: language)
        let tag = NSSpellChecker.uniqueSpellDocumentTag()
        defer { checker.closeSpellDocument(withTag: tag) }

        var spans: [CorrectionSpan] = []
        var startAt = 0

        while startAt < (text as NSString).length {
            var details: NSArray? = nil
            let range = checker.checkGrammar(
                of: text, startingAt: startAt, language: locale,
                wrap: false, inSpellDocumentWithTag: tag, details: &details)
            guard range.location != NSNotFound else { break }

            if let detailsArray = details as? [[String: Any]] {
                for detail in detailsArray {
                    guard let grammarRange = detail["NSGrammarRange"] as? NSRange,
                          grammarRange.location != NSNotFound,
                          let swiftRange = Range(grammarRange, in: text) else { continue }
                    let original = String(text[swiftRange])
                    let corrections = detail["NSGrammarCorrections"] as? [String] ?? []
                    let description = detail["NSGrammarUserDescription"] as? String ?? "Grammar error"
                    guard let replacement = corrections.first, replacement != original else { continue }
                    spans.append(CorrectionSpan(
                        range: grammarRange, original: original, replacement: replacement,
                        reason: description, confidence: 0.80, source: .nativeGrammar))
                }
            }
            startAt = range.location + max(1, range.length)
        }
        return spans
    }
}
