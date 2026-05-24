import Foundation
import NaturalLanguage

enum DraftDetector {
    struct Score {
        let value: Double   // 0.0 – 1.0
        let isDraft: Bool   // value >= threshold
        let detectedLanguage: String?
        let likelyRecipient: String?
        let messageType: MessageType
    }

    enum MessageType: String {
        case email, chat, generic
    }

    private static let threshold: Double = 0.55

    static func score(_ text: String) -> Score {
        let words = text.split(separator: " ").map(String.init)
        let wordCount = words.count
        guard wordCount >= 2 else {
            return Score(value: 0, isDraft: false, detectedLanguage: nil, likelyRecipient: nil, messageType: .generic)
        }

        var points: Double = 0
        var maxPoints: Double = 0

        // Short text → likely draft notes
        maxPoints += 2
        if wordCount < 15 { points += 2 }
        else if wordCount < 30 { points += 1 }

        // Low ratio of uppercase starts → sentence fragments
        maxPoints += 2
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let uppercaseStartRatio: Double = sentences.isEmpty ? 0 :
            Double(sentences.filter { $0.first?.isUppercase == true }.count) / Double(sentences.count)
        if uppercaseStartRatio < 0.5 { points += 2 }
        else if uppercaseStartRatio < 0.8 { points += 1 }

        // No punctuation → fragment style
        maxPoints += 1
        let hasSentenceEnding = text.contains(".") || text.contains("!") || text.contains("?")
        if !hasSentenceEnding { points += 1 }

        // Role / contact keywords
        maxPoints += 2
        let lower = text.lowercased()
        let roleKeywords = ["professor", "prof", "capo", "collega", "dott", "ingegner",
                            "direttore", "responsabile", "recruiter", "hr", "cliente",
                            "fornitore", "segreteria", "ufficio"]
        if roleKeywords.contains(where: { lower.contains($0) }) { points += 2 }

        // Email-specific keywords
        maxPoints += 1
        let emailKeywords = ["email", "mail", "messaggio", "richiesta", "informazioni",
                             "colloquio", "appuntamento", "disponibilità", "preventivo",
                             "ringraziamento", "conferma", "reminder", "follow"]
        if emailKeywords.contains(where: { lower.contains($0) }) { points += 1 }

        let finalScore = points / maxPoints

        let detectedLanguage = detectLanguage(text)
        let recipient = extractRecipient(from: text)
        let msgType = detectMessageType(text)

        return Score(
            value: finalScore,
            isDraft: finalScore >= threshold,
            detectedLanguage: detectedLanguage,
            likelyRecipient: recipient,
            messageType: msgType
        )
    }

    private static func detectLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    private static func extractRecipient(from text: String) -> String? {
        let lower = text.lowercased()
        let recipientPatterns: [(keyword: String, role: String)] = [
            ("professor", "professor"),
            ("prof ", "professor"),
            ("prof.", "professor"),
            ("dott.", "dottore"),
            ("dott ", "dottore"),
            ("ingegner", "ingegnere"),
            ("direttore", "direttore"),
            ("capo", "manager"),
            ("collega", "collega"),
            ("recruiter", "recruiter"),
            ("hr", "HR"),
            ("cliente", "cliente"),
        ]
        for (keyword, role) in recipientPatterns {
            if lower.contains(keyword) { return role }
        }
        return nil
    }

    private static func detectMessageType(_ text: String) -> MessageType {
        let lower = text.lowercased()
        let emailIndicators = ["email", "mail", "richiesta", "oggetto", "allego",
                               "cordiali saluti", "buongiorno", "gentile"]
        for indicator in emailIndicators {
            if lower.contains(indicator) { return .email }
        }
        return .generic
    }
}
