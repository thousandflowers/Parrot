import Foundation
import NaturalLanguage

struct LanguageDetector {
    static func detect(text: String, fallbackLanguage: String) -> String {
        guard text.count >= 12 else { return fallbackLanguage }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return fallbackLanguage }
        return dominant.rawValue
    }
}
