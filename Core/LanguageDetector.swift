import Foundation
import NaturalLanguage

struct LanguageDetector {
    static func detect(text: String, fallbackLanguage: String) -> String {
        let minLength = containsCJK(text) ? 2 : 12
        guard text.count >= minLength else { return fallbackLanguage }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return fallbackLanguage }
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
