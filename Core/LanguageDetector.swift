import Foundation
import NaturalLanguage

struct LanguageDetector {
    /// Rileva la lingua principale del testo.
    static func detect(text: String, fallbackLanguage: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return fallbackLanguage }
        return dominant.rawValue
    }

    /// Rileva la lingua di ogni frase nel testo.
    /// Restituisce array di (frase, lingua) per gestire testi multilingue.
    static func detectSentenceLanguages(text: String, fallbackLanguage: String) -> [(sentence: String, language: String)] {
        let separators = CharacterSet(charactersIn: ".!?\n")
        let sentences = text.components(separatedBy: separators).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return sentences.map { sentence in
            let lang = detect(text: sentence.trimmingCharacters(in: .whitespaces), fallbackLanguage: fallbackLanguage)
            return (sentence, lang)
        }
    }
}
