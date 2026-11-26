import Foundation
import NaturalLanguage

struct LanguageDetector {
    /// CJK: 2 characters already carry enough signal.
    static let cjkMinLength = 2
    /// Below this, even a confident guess is noise ("hi" → Catalan 0.80).
    static let shortTextMinLength = 4
    /// From this length on, NLLanguageRecognizer is reliable at a moderate confidence.
    static let longTextMinLength = 20
    static let longTextMinConfidence = 0.55
    /// Short Latin-script phrases are often misclassified as a sibling language, so a short
    /// text only overrides the fallback when the recognizer is very sure
    /// ("Ciao, come stai?" → it 0.96; "I has a cat" → ca 0.73 → fallback kept).
    static let shortTextMinConfidence = 0.90

    static func detect(text: String, fallbackLanguage: String) -> String {
        let isCJK = containsCJK(text)
        guard text.count >= (isCJK ? cjkMinLength : shortTextMinLength) else { return fallbackLanguage }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return fallbackLanguage }
        let confidence = recognizer.languageHypotheses(withMaximum: 1)[dominant] ?? 0
        let isLong = isCJK || text.count >= longTextMinLength
        let required = isLong ? longTextMinConfidence : shortTextMinConfidence
        guard confidence >= required else { return fallbackLanguage }
        return dominant.rawValue
    }

    /// Primary language subtag, lowercased: "zh-Hans" → "zh", "en_US" → "en".
    static func primarySubtag(_ code: String) -> String {
        String(code.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? Substring(code)).lowercased()
    }

    /// Compares two language codes by primary subtag, so "zh" and "zh-Hans" are the same language.
    static func isSameLanguage(_ lhs: String, _ rhs: String) -> Bool {
        primarySubtag(lhs) == primarySubtag(rhs)
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)  // CJK Unified
            || (0x3040...0x30FF).contains(scalar.value) // Hiragana/Katakana
            || (0xAC00...0xD7AF).contains(scalar.value) // Hangul
        }
    }
}
