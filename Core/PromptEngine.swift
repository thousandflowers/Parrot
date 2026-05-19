import Foundation
import OSLog
import AppKit

enum LanguageFamily: String {
    case latin
    case cjk
    case slavic
    case arabic
    case nordic

    static func family(for languageCode: String) -> LanguageFamily {
        let primary = languageCode.split(separator: "-").first.map(String.init) ?? languageCode
        switch primary {
        case "zh", "ja", "ko":                         return .cjk
        case "ru", "pl", "cs", "uk", "bg", "sr", "hr": return .slavic
        case "ar", "fa", "he", "ur":                   return .arabic
        case "sv", "da", "no", "fi", "is":             return .nordic
        default:                                        return .latin
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

    init(language: String = "en", style: String = "equilibrato") {
        self.language = language
        self.style = style
    }

    private var grammarFamilyInstruction: String {
        switch LanguageFamily.family(for: language) {
        case .latin:  return ""
        case .cjk:    return "Preserve full-width punctuation. Do not convert to ASCII. Pay attention to correct measure words, particles, and aspect markers."
        case .arabic: return "Preserve right-to-left text direction and Arabic punctuation."
        case .slavic: return "Pay attention to case declensions and aspect of verbs. Preserve all diacritical characters exactly (č, ć, š, ž, đ, ź, ń, ř, etc.)."
        case .nordic: return "Preserve special characters exactly (å, ä, ö, ø, æ, ð, þ)."
        }
    }

    private var styleInstruction: String {
        switch style {
        case "formale":    return "Use formal, professional tone."
        case "informale":  return "Use casual, conversational tone."
        case "accademico": return "Use academic, scholarly tone."
        case "tecnico":    return "Use precise, technical language appropriate for documentation or code comments."
        default:           return ""
        }
    }

    private func flagSuspiciousWords(_ text: String) -> [String] {
        guard LanguageFamily.family(for: language) != .cjk else { return [] }
        let spellChecker = NSSpellChecker.shared
        let words = text.split(separator: " ")
        var flagged: [String] = []

        for word in words {
            let wordStr = String(word)
            let trimmed = wordStr.trimmingCharacters(in: .punctuationCharacters)
            guard trimmed.count > 2 else { continue }
            guard !IgnoreList.isIgnored(trimmed) else { continue }

            let range = spellChecker.checkSpelling(of: wordStr, startingAt: 0,
                language: language.starts(with: "en") ? "en" : language,
                wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)

            if range.location != NSNotFound {
                flagged.append(wordStr)
            }
        }

        return flagged
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

        let flagged = flagSuspiciousWords(text)
        let safeText = escapeForPrompt(text)

        var header = "Correct only genuine errors in grammar, spelling, and punctuation. Preserve the original style, register, tone, and vocabulary level exactly. Do not simplify or change the author's voice."
        if !extra.isEmpty { header += "\n\(extra)" }
        if !styleLine.isEmpty { header += "\n\(styleLine)" }
        if !flagged.isEmpty {
            header += "\nNote: These words might be misspelled: \(flagged.joined(separator: ", ")). Use your context to decide if they need fixing."
        }
        header += "\n\nExample corrections:\n\(fewShotExamples())"

        return """
        \(header)

        <TEXT>\(safeText)</TEXT>\(customInstruction.map { "\n<CUSTOM>\($0)</CUSTOM>" } ?? "")

        Output only the corrected text; no notes or explanations. Do not include <TEXT>/<CUSTOM> tags.
        """
    }

    private func fewShotExamples() -> String {
        let primary = language.split(separator: "-").first.map(String.init) ?? language
        switch primary {
        case "it":
            return "Input: \"Io andato al mercato ieri.\"\nOutput: \"Io sono andato al mercato ieri.\"\n\nInput: \"Li ragazzi gioca a calcio nel parco.\"\nOutput: \"I ragazzi giocano a calcio nel parco.\""
        case "fr":
            return "Input: \"Je suis allé à le magasin hier.\"\nOutput: \"Je suis allé au magasin hier.\"\n\nInput: \"Il as mangé une pomme.\"\nOutput: \"Il a mangé une pomme.\""
        case "da":
            return "Input: \"Jeg er gå til butikken i går.\"\nOutput: \"Jeg gik til butikken i går.\"\n\nInput: \"Han har spise et æble.\"\nOutput: \"Han har spist et æble.\""
        case "hr":
            return "Input: \"Ja sam ido u trgovinu jučer.\"\nOutput: \"Ja sam otišao u trgovinu jučer.\"\n\nInput: \"Djeca igraju se u parku.\"\nOutput: \"Djeca se igraju u parku.\""
        case "zh":
            return "Input: \"我非常的喜欢吃苹果。\"\nOutput: \"我非常喜欢吃苹果。\"\n\nInput: \"他昨天去了商店买了一些东西买了。\"\nOutput: \"他昨天去了商店买了一些东西。\""
        default:
            return "Input: \"He go to the store yesterday.\"\nOutput: \"He went to the store yesterday.\"\n\nInput: \"The cats is sleeping on the couch.\"\nOutput: \"The cats are sleeping on the couch.\""
        }
    }

    func buildFluencyPrompt(for text: String, customInstruction: String? = nil) -> String {
        let styleLine = styleInstruction
        let safeText = escapeForPrompt(text)
        var header = "Improve fluency and naturalness only; do not fix grammar already correct."
        if !styleLine.isEmpty { header += "\n\(styleLine)" }
        header += "\n\nExample:\nInput: \"The project was completed. The team celebrated. It was good.\"\nOutput: \"After completing the project, the team celebrated. It was a rewarding experience.\""
        return """
        \(header)

        <TEXT>\(safeText)</TEXT>\(customInstruction.map { "\n<CUSTOM>\($0)</CUSTOM>" } ?? "")

        Output only the improved text; no notes or explanations. Do not include <TEXT>/<CUSTOM> tags.
        """
    }

    func buildExplainPrompt(original: String, corrected: String, customInstruction: String? = nil) -> String {
        let styleLine = styleInstruction
        let langName = englishLanguageName(for: language)
        var instruction = "Explain the grammar, spelling, or style errors corrected in this text. Be concise. Explain in \(langName)."
        if !styleLine.isEmpty { instruction += " \(styleLine)" }
        if let custom = customInstruction { instruction += " \(custom)" }
        let safeOriginal = escapeForPrompt(original)
        let safeCorrected = escapeForPrompt(corrected)
        return "\(instruction)\n\nORIGINAL: \(safeOriginal)\nCORRECTED: \(safeCorrected)\nEXPLANATION:"
    }

    func buildCoachPrompt(for text: String) -> String {
        let langName = englishLanguageName(for: language)
        let family = grammarFamilyInstruction
        var instruction = """
        Analyze the following text as a professional writing teacher. Provide structured feedback in 4 categories:

        1. **Grammar**: spelling, grammar, and punctuation errors
        2. **Style**: repetitions, overly long sentences, weak words, passive voice
        3. **Tone**: register consistency, contextual appropriateness
        4. **Clarity**: ambiguities, logical structure, flow of ideas

        For each category, list:
        - Specific issues found (with quotes from the text)
        - Concrete suggestions for improvement
        - An example of how to rewrite it

        Output language must be \(langName). Be constructive and specific.
        """
        if !family.isEmpty { instruction += "\n\n\(family)" }
        let safeText = escapeForPrompt(text)
        return "\(instruction)\n\nTEXT TO ANALYZE: \(safeText)\n\nANALYSIS:"
    }

    private func englishLanguageName(for code: String) -> String {
        // Check full code first to distinguish Chinese variants
        switch code {
        case "zh-Hans", "zh-CN": return "Simplified Chinese"
        case "zh-Hant", "zh-TW", "zh-HK": return "Traditional Chinese"
        default: break
        }
        let primary = code.split(separator: "-").first.map(String.init) ?? code
        switch primary {
        case "it": return "Italian"
        case "en": return "English"
        case "fr": return "French"
        case "de": return "German"
        case "es": return "Spanish"
        case "pt": return "Portuguese"
        case "ru": return "Russian"
        case "zh": return "Chinese"
        case "ja": return "Japanese"
        case "ar": return "Arabic"
        case "hr": return "Croatian"
        case "da": return "Danish"
        case "nb", "no": return "Norwegian"
        case "el": return "Greek"
        case "nl": return "Dutch"
        case "pl": return "Polish"
        case "sv": return "Swedish"
        case "ko": return "Korean"
        case "tr": return "Turkish"
        default:   return code
        }
    }

    func buildCustomPrompt(text: String, custom: CustomPrompt) -> String {
        custom.buildPrompt(for: text, language: language)
    }

    func buildTranslationPrompt(for text: String, targetLanguage: String) -> String {
        let escaped = escapeForPrompt(text)
        let langName = Locale.current.localizedString(forLanguageCode: targetLanguage) ?? targetLanguage
        return """
        Translate the following text into \(langName). Output only the translated text, nothing else.

        <TEXT>\(escaped)</TEXT>
        """
    }

    func buildPrompt(for text: String, type: PromptType, customInstruction: String? = nil) -> String {
        switch type {
        case .grammar:
            return buildGrammarPrompt(for: text, customInstruction: customInstruction)
        case .fluency:
            return buildFluencyPrompt(for: text, customInstruction: customInstruction)
        case .explain:
            let safeText = escapeForPrompt(text)
            Logger.core.debug("buildPrompt called with .explain — use buildExplainPrompt(original:corrected:) directly")
            return """
            Explain any errors in the following text.

            <TEXT>\(safeText)</TEXT>\(customInstruction.map { "\n<CUSTOM>\($0)</CUSTOM>" } ?? "")

            Output only your explanation. Do not include <TEXT>/<CUSTOM> tags.
            """
        case .coach:
            return buildCoachPrompt(for: text)
        case .translation(let targetLanguage):
            return buildTranslationPrompt(for: text, targetLanguage: targetLanguage)
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
