import Foundation
import os

enum LanguageFamily: String {
    case latin
    case cjk
    case slavic
    case arabic
    case nordic

    static func family(for languageCode: String) -> LanguageFamily {
        let primary = languageCode.split(separator: "-").first.map(String.init) ?? languageCode
        switch primary {
        case "zh", "ja", "ko":                    return .cjk
        case "ru", "pl", "cs", "uk", "bg", "sr": return .slavic
        case "ar", "fa", "he", "ur":              return .arabic
        case "sv", "da", "no", "fi", "is":        return .nordic
        default:                                   return .latin
        }
    }
}

struct CustomPrompt: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var template: String
    var checkType: CheckType
    var icon: String
    var shortcutKey: String?

    enum CheckType: String, Codable, CaseIterable {
        case grammar
        case fluency
        case custom
    }

    enum CodingKeys: CodingKey {
        case id, name, template, checkType, icon, shortcutKey
    }

    init(id: UUID = UUID(), name: String, template: String, checkType: CheckType = .custom,
         icon: String = "pencil", shortcutKey: String? = nil) {
        self.id = id
        self.name = name
        self.template = template
        self.checkType = checkType
        self.icon = icon
        self.shortcutKey = shortcutKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.template = try container.decode(String.self, forKey: .template)
        self.checkType = try container.decodeIfPresent(CheckType.self, forKey: .checkType) ?? .custom
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "pencil"
        self.shortcutKey = try container.decodeIfPresent(String.self, forKey: .shortcutKey)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(template, forKey: .template)
        try container.encode(checkType, forKey: .checkType)
        try container.encode(icon, forKey: .icon)
        try container.encodeIfPresent(shortcutKey, forKey: .shortcutKey)
    }

    func buildPrompt(for text: String, language: String) -> String {
        template
            .replacingOccurrences(of: "{{TEXT}}", with: text)
            .replacingOccurrences(of: "{{LANGUAGE}}", with: language)
    }
}

struct PromptEngine {
    private var language: String
    private var style: String

    init(language: String = "it", style: String = "equilibrato") {
        self.language = language
        self.style = style
    }

    private var grammarFamilyInstruction: String {
        switch LanguageFamily.family(for: language) {
        case .latin:  return ""
        case .cjk:    return "Preserve full-width punctuation. Do not convert to ASCII."
        case .arabic: return "Preserve right-to-left text direction and Arabic punctuation."
        case .slavic: return "Pay attention to case declensions and aspect of verbs."
        case .nordic: return "Preserve special characters (å, ä, ö, ø, æ, ð, þ)."
        }
    }

    private var styleInstruction: String {
        switch style {
        case "formale":         return "Use formal, professional tone."
        case "informale":       return "Use casual, conversational tone."
        case "accademico":      return "Use academic, scholarly tone."
        default:                return ""
        }
    }

    private func escapeForPrompt(_ text: String) -> String {
        var escaped = text
        if escaped.contains("<TEXT>") {
            escaped = escaped.replacingOccurrences(of: "<TEXT>", with: "<\\TEXT>")
        }
        if escaped.contains("</TEXT>") {
            escaped = escaped.replacingOccurrences(of: "</TEXT>", with: "<\\/TEXT>")
        }
        if escaped.contains("<CUSTOM>") {
            escaped = escaped.replacingOccurrences(of: "<CUSTOM>", with: "<\\CUSTOM>")
        }
        if escaped.contains("</CUSTOM>") {
            escaped = escaped.replacingOccurrences(of: "</CUSTOM>", with: "<\\/CUSTOM>")
        }
        return escaped
    }

    func buildGrammarPrompt(for text: String, customInstruction: String? = nil) -> String {
        let extra = grammarFamilyInstruction
        let styleLine = styleInstruction
        let langName = localizedLanguageName(for: language)
        var instruction = "Riscrivi il testo correggendo solo gli errori grammaticali e ortografici. Non modificare significato, stile o lingua. La lingua di output deve essere \(langName)."
        if !extra.isEmpty { instruction += " \(extra)" }
        if !styleLine.isEmpty { instruction += " \(styleLine)" }
        if let custom = customInstruction { instruction += " \(custom)" }
        let safeText = escapeForPrompt(text)
        return """
        \(instruction)

        TESTO: io volebbi un caffè
        CORREZIONE: io voglio un caffè

        TESTO: \(safeText)
        CORREZIONE:
        """
    }

    func buildFluencyPrompt(for text: String, customInstruction: String? = nil) -> String {
        let styleLine = styleInstruction
        let langName = localizedLanguageName(for: language)
        var instruction = "Riscrivi il testo migliorando la fluidità e la naturalezza, mantenendo il significato originale. La lingua di output deve essere \(langName). Non tradurre."
        if !styleLine.isEmpty { instruction += " \(styleLine)" }
        if let custom = customInstruction { instruction += " \(custom)" }
        let safeText = escapeForPrompt(text)
        return "\(instruction)\n\nTESTO: \(safeText)\nCORREZIONE:"
    }

    func buildExplainPrompt(original: String, corrected: String, customInstruction: String? = nil) -> String {
        let styleLine = styleInstruction
        var instruction = "Explain the grammar, spelling, or style errors corrected in this text. Be concise. Explain in \(language)."
        if !styleLine.isEmpty { instruction += " \(styleLine)" }
        if let custom = customInstruction { instruction += " \(custom)" }
        let safeOriginal = escapeForPrompt(original)
        let safeCorrected = escapeForPrompt(corrected)
        return "\(instruction)\n\nORIGINAL: \(safeOriginal)\nCORRECTED: \(safeCorrected)\nEXPLANATION:"
    }

    func buildCoachPrompt(for text: String) -> String {
        let langName = localizedLanguageName(for: language)
        let family = grammarFamilyInstruction
        var instruction = """
        Analizza il seguente testo come un insegnante di scrittura professionista. Fornisci feedback strutturato in 4 categorie:

        1. **Grammatica**: errori ortografici, grammaticali, di punteggiatura
        2. **Stile**: ripetizioni, frasi troppo lunghe, parole deboli, voce passiva
        3. **Tono**: coerenza del registro, appropriatezza al contesto
        4. **Chiarezza**: ambiguità, struttura logica, flusso delle idee

        Per ogni categoria, elenca:
        - I problemi specifici trovati (con citazioni dal testo)
        - Suggerimenti concreti per migliorare
        - Un esempio di come riscrivere

        La lingua di output deve essere \(langName). Sii costruttivo e specifico.
        """
        if !family.isEmpty { instruction += "\n\n\(family)" }
        let safeText = escapeForPrompt(text)
        return "\(instruction)\n\nTESTO DA ANALIZZARE: \(safeText)\n\nANALISI:"
    }

    private func localizedLanguageName(for code: String) -> String {
        let primary = code.split(separator: "-").first.map(String.init) ?? code
        switch primary {
        case "it": return "italiano"
        case "en": return "inglese"
        case "fr": return "francese"
        case "de": return "tedesco"
        case "es": return "spagnolo"
        case "pt": return "portoghese"
        case "ru": return "russo"
        case "zh": return "cinese"
        case "ja": return "giapponese"
        case "ar": return "arabo"
        default:   return code
        }
    }

    func buildCustomPrompt(text: String, custom: CustomPrompt) -> String {
        custom.buildPrompt(for: text, language: language)
    }

    func buildPrompt(for text: String, type: PromptType, customInstruction: String? = nil) -> String {
        switch type {
        case .grammar:
            return buildGrammarPrompt(for: text, customInstruction: customInstruction)
        case .fluency:
            return buildFluencyPrompt(for: text, customInstruction: customInstruction)
        case .explain:
            let safeText = escapeForPrompt(text)
            os_log(.debug, "buildPrompt called with .explain — use buildExplainPrompt(original:corrected:) directly")
            return """
            Explain any errors in the following text.

            <TEXT>\(safeText)</TEXT>\(customInstruction.map { "\n<CUSTOM>\($0)</CUSTOM>" } ?? "")

            Output only your explanation. Do not include <TEXT>/<CUSTOM> tags.
            """
        case .coach:
            return buildCoachPrompt(for: text)
        case .translation(let targetLanguage):
            let safeText = escapeForPrompt(text)
            return """
            Translate the following text to \(targetLanguage). Output only the translation, nothing else.
            <TEXT>\(safeText)</TEXT>
            """
        case .custom(_, let template):
            var result = template
                .replacingOccurrences(of: "{{TEXT}}", with: text)
                .replacingOccurrences(of: "{{LANGUAGE}}", with: language)
            if let instruction = customInstruction {
                result += "\n<CUSTOM>\(instruction)</CUSTOM>"
            }
            return result
        }
    }
}
