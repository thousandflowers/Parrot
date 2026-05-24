import Foundation
import NaturalLanguage

enum ContactInferrer {
    struct InferredContact {
        var name: String?
        var role: String?
        var formality: ContactProfile.Formality
        var salutation: String?
        var closing: String?
    }

    static func infer(from expandedText: String, draftHint: String) -> InferredContact {
        let lower = expandedText.lowercased()
        let formality = detectFormality(lower)
        let name = extractName(from: expandedText)
        let role = extractRole(from: draftHint + " " + expandedText)
        let salutation = extractSalutation(from: expandedText)
        let closing = extractClosing(from: expandedText)
        return InferredContact(
            name: name,
            role: role,
            formality: formality,
            salutation: salutation,
            closing: closing
        )
    }

    private static func detectFormality(_ lower: String) -> ContactProfile.Formality {
        let formalMarkers = ["gentile", "egregio", "spettabile", "cordiali saluti",
                             "distinti saluti", "le porgo", "la contatto", "la ringrazio"]
        let informalMarkers = ["ciao", "salve!", "a presto", "un abbraccio", "grazie mille!",
                               "ci sentiamo", "ti scrivo"]
        let formalScore = formalMarkers.filter { lower.contains($0) }.count
        let informalScore = informalMarkers.filter { lower.contains($0) }.count
        if formalScore > informalScore { return .formal }
        if informalScore > formalScore { return .informal }
        return .semiformal
    }

    private static func extractName(from text: String) -> String? {
        // Look for "Gentile Prof. Rossi" or "Caro Marco" patterns
        let patterns = [
            #"Gentile\s+(?:Prof(?:essore?)?\.?\s+|Dott(?:\.)?\.?\s+|Ing\.?\s+)?([A-Z][a-zA-Zàèìòù]+(?:\s+[A-Z][a-zA-Zàèìòù]+)?)"#,
            #"Caro/a\s+([A-Z][a-zA-Zàèìòù]+)"#,
            #"Caro\s+([A-Z][a-zA-Zàèìòù]+)"#,
            #"Cara\s+([A-Z][a-zA-Zàèìòù]+)"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: text) {
                return String(text[range])
            }
        }
        return nil
    }

    private static func extractRole(from text: String) -> String? {
        let lower = text.lowercased()
        let roleMap: [(keyword: String, role: String)] = [
            ("professor", "professore"),
            ("prof ", "professore"),
            ("dott.", "dottore"),
            ("ingegner", "ingegnere"),
            ("direttore", "direttore"),
            ("responsabile", "responsabile"),
            ("capo", "manager"),
            ("collega", "collega"),
            ("recruiter", "recruiter"),
            ("hr", "HR"),
            ("cliente", "cliente"),
            ("fornitore", "fornitore"),
        ]
        for (keyword, role) in roleMap {
            if lower.contains(keyword) { return role }
        }
        return nil
    }

    private static func extractSalutation(from text: String) -> String? {
        // First non-empty line that looks like a salutation
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        for line in lines {
            let low = line.lowercased()
            if low.hasPrefix("gentile") || low.hasPrefix("caro") || low.hasPrefix("cara")
                || low.hasPrefix("egregio") || low.hasPrefix("spettabile") {
                return line.trimmingCharacters(in: CharacterSet(charactersIn: ","))
            }
        }
        return nil
    }

    private static func extractClosing(from text: String) -> String? {
        // Last meaningful line before empty lines at end
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for line in lines.reversed() {
            let low = line.lowercased()
            if low.contains("saluti") || low.contains("cordialmente") || low.contains("a presto")
                || low.contains("distinti") || low.contains("grazie") || low.contains("un saluto") {
                return line
            }
        }
        return nil
    }
}
