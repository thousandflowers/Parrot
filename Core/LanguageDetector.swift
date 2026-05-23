import Foundation
import NaturalLanguage

struct LanguageDetector {
    static func detect(text: String, fallbackLanguage: String) -> String {
        // CJK: 2 chars is enough for reliable detection.
        // Non-CJK: NLLanguageRecognizer is unreliable below ~20 chars — short phrases like
        // "Sono pronto" or "Bonjour" are often misclassified as a wrong Romance language.
        // Use a higher threshold and require a confidence of at least 0.55 before trusting the result.
        let minLength = containsCJK(text) ? 2 : 20
        guard text.count >= minLength else { return fallbackLanguage }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return fallbackLanguage }
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        let confidence = hypotheses[dominant] ?? 0
        guard confidence >= 0.55 else { return fallbackLanguage }
        return dominant.rawValue
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)  // CJK Unified
            || (0x3040...0x30FF).contains(scalar.value) // Hiragana/Katakana
            || (0xAC00...0xD7AF).contains(scalar.value) // Hangul
        }
    }
}
