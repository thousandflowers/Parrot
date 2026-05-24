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
        case "zh", "ja", "ko", "yue", "th", "my", "km":
            return .cjk
        case "ru", "pl", "cs", "uk", "bg", "sr", "hr", "sk", "sl", "mk", "be":
            return .slavic
        case "ar", "fa", "he", "ur", "ps", "sd":
            return .arabic
        case "sv", "da", "no", "nb", "nn", "fi", "is", "et", "lv", "lt":
            return .nordic
        default:
            return .latin
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
    private let language: String
    private let style: String
    private let primaryLanguageCode: String
    private let languageFamily: LanguageFamily

    init(language: String = "en", style: String = "equilibrato") {
        self.language = language
        self.style = style
        self.primaryLanguageCode = language.split(separator: "-").first.map(String.init) ?? language
        self.languageFamily = LanguageFamily.family(for: language)
    }

    private var grammarFamilyInstruction: String {
        switch languageFamily {
        case .latin:
            return "Fix inflection errors — wrong verb conjugation (person, number, tense, or mood), noun/adjective/article agreement, and required prepositions. When syntax demands a specific grammatical mood (subjunctive, conditional, etc.), use it; do NOT substitute a different mood or tense when both are grammatically valid."
        case .cjk:
            return "Preserve CJK punctuation and do not convert to ASCII. Fix particles, measure words, aspect markers, and collocations. Do not rewrite sentences that are already correct."
        case .arabic:
            return "Preserve right-to-left text and Arabic punctuation. Fix verb-subject agreement, broken plurals, and definite article (ال) usage."
        case .slavic:
            return "Fix case declension, verb aspect (perfective/imperfective), and gender agreement. Preserve all diacritical characters exactly."
        case .nordic:
            return "Fix noun gender agreement and verb conjugation. Preserve special characters exactly."
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
        guard languageFamily != .cjk else { return [] }
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
        escaped = escaped.replacingOccurrences(of: "</CUSTOM>", with: "<\\/CUSTOM>")
        escaped = escaped.replacingOccurrences(of: "<CUSTOM>", with: "<\\CUSTOM>")
        escaped = escaped.replacingOccurrences(of: "</TEXT>", with: "<\\/TEXT>")
        escaped = escaped.replacingOccurrences(of: "<TEXT>", with: "<\\TEXT>")
        return escaped
    }

    func buildGrammarPrompt(for text: String, customInstruction: String? = nil) -> String {
        let extra = grammarFamilyInstruction
        let styleLine = styleInstruction
        let safeText = escapeForPrompt(text)

        var parts: [String] = []
        parts.append("Fix all grammatical errors in the text inside <TEXT>: misspellings, wrong verb forms, wrong agreement, and broken phrases where the words as written are syntactically impossible. You may add or replace words ONLY to fix a clear grammatical error — for example, add a missing verb form or replace a wrong form. Do not rephrase correct sentences, do not reorder, do not substitute synonyms. Return only the corrected text.")
        if !extra.isEmpty { parts.append(extra) }
        if !styleLine.isEmpty { parts.append(styleLine) }
        if let custom = customInstruction { parts.append(custom) }
        if let styleHint = StyleProfiler.buildHint(language: language) { parts.append(styleHint) }
        parts.append("\n<TEXT>\(safeText)</TEXT>")

        return parts.joined(separator: "\n")
    }

    func buildGrammarJSONPrompt(for text: String) -> String {
        let extra = grammarFamilyInstruction
        let safeText = escapeForPrompt(text)
        var lines: [String] = []
        lines.append("""
        Find grammar errors in the text inside <TEXT>. Return ONLY valid JSON — no prose, no markdown. \
        If no corrections needed, return {"corrections":[]}. \
        Schema: {"corrections":[{"original":"<exact substring>","replacement":"<corrected>","reason":"<brief reason in input language>"}]} \
        Rules: "original" must be exact substring of input. Fix only clear errors. Do not rephrase, reorder, or translate.
        """)
        if !extra.isEmpty { lines.append(extra) }
        lines.append("\n<TEXT>\(safeText)</TEXT>")
        return lines.joined(separator: "\n")
    }

    func buildFluencyPrompt(for text: String, customInstruction: String? = nil) -> String {
        let styleLine = styleInstruction
        let safeText = escapeForPrompt(text)
        var lines: [String] = []
        lines.append("Rewrite the text to improve readability, flow, and naturalness. Combine short choppy sentences. Use varied sentence structure. Preserve the original meaning exactly — do NOT add, invent, or assume any information not present in the original. Only words and facts already in the text may appear in the output. Output ONLY the rewritten text IN THE SAME LANGUAGE as the input. Do NOT translate.")
        if !styleLine.isEmpty { lines.append(styleLine) }
        if let custom = customInstruction { lines.append(custom) }
        lines.append("\n<TEXT>\(safeText)</TEXT>")

        return lines.joined(separator: "\n")
    }

    func buildCombinedPrompt(for text: String) -> String {
        let extra = grammarFamilyInstruction
        let styleLine = styleInstruction
        let safeText = escapeForPrompt(text)
        var parts: [String] = []
        parts.append("Fix all grammatical errors AND improve the fluency and natural flow of the text inside <TEXT>. Fix: misspellings, wrong verb forms, wrong agreement, broken phrases. Also: improve awkward phrasing, vary repetitive sentence structure, smooth transitions. Preserve the author's voice and original meaning — do not add information or change the intent. Output only the corrected text in the same language as the input.")
        if !extra.isEmpty { parts.append(extra) }
        if !styleLine.isEmpty { parts.append(styleLine) }
        if let styleHint = StyleProfiler.buildHint(language: language) { parts.append(styleHint) }
        parts.append("\n<TEXT>\(safeText)</TEXT>")
        return parts.joined(separator: "\n")
    }

    func buildExplainPrompt(original: String, corrected: String, customInstruction: String? = nil) -> String {
        let styleLine = styleInstruction
        var instruction = "Explain the grammar, spelling, or style errors corrected in this text. Be concise. Respond in the same language as the text."
        if !styleLine.isEmpty { instruction += " \(styleLine)" }
        if let custom = customInstruction { instruction += " \(custom)" }
        let safeOriginal = escapeForPrompt(original)
        let safeCorrected = escapeForPrompt(corrected)
        return "\(instruction)\n\nORIGINAL: \(safeOriginal)\nCORRECTED: \(safeCorrected)"
    }

    func buildCoachPrompt(for text: String) -> String {
        let safeText = escapeForPrompt(text)
        return """
        You are a writing coach. Respond in the same language as the text below. \
        List only the real issues you can see — grammar errors, unclear phrasing, awkward word choices. \
        For each issue: quote the exact problematic part, explain what is wrong, give a corrected version. \
        If there are no significant issues, say so briefly. Do not invent issues that are not in the text.

        <TEXT>\(safeText)</TEXT>
        """
    }

    private func languageName(for code: String) -> String {
        Locale(identifier: "en_US").localizedString(forLanguageCode: code) ?? code
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
            assertionFailure("Use buildExplainPrompt(original:corrected:) instead of buildPrompt(for:type:) with .explain")
            return buildGrammarPrompt(for: text, customInstruction: customInstruction)
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
        case .grammarAndFluency:
            return buildCombinedPrompt(for: text)
        case .deSlop:
            return buildDeSlopPrompt(for: text)
        case .aiPrompt:
            return buildAIPromptPrompt(for: text)
        case .expand:
            return buildExpandPrompt(for: text, contactProfile: nil)
        }
    }

    func buildDeSlopPrompt(for text: String) -> String {
        let safeText = escapeForPrompt(text)
        let langName = languageName(for: language)
        return """
        Rewrite the following text to sound more human and natural. Remove AI-sounding patterns including:
        - Overused AI phrases: "delve", "testament", "tapestry", "it's important to note", "in conclusion", "foster", "leverage"
        - Overly perfect sentence structure that feels robotic
        - Repetitive transition words and formulaic paragraph openings
        - Excessive hedging or qualifier stacking
        - Generic, soulless phrasing that could apply to anything

        Preserve the original meaning, facts, and intent. Keep the same language. Output ONLY the rewritten text.

        <TEXT>\(safeText)</TEXT>
        """
    }

    func buildAIPromptPrompt(for text: String) -> String {
        let safeText = escapeForPrompt(text)
        return """
        Rewrite the following text to make it an effective prompt for an AI assistant. Apply these transformations:
        - Clarify ambiguous references and implicit context
        - Structure with clear sections: context, task, constraints, output format
        - Remove filler and redundancy
        - Add specific instructions about tone, length, and format if not already present
        - Use markdown formatting for readability
        - Preserve all original facts and intent

        Output ONLY the optimized prompt text.

        <TEXT>\(safeText)</TEXT>
        """
    }

    func buildExpandPrompt(for text: String, contactProfile: ContactProfile?) -> String {
        let safeText = escapeForPrompt(text)
        let langName = languageName(for: language)

        var contextLines: [String] = []
        if let p = contactProfile {
            contextLines.append("Recipient: \(p.name)")
            if !p.role.isEmpty  { contextLines.append("Role: \(p.role)") }
            contextLines.append("Formality: \(p.formality.rawValue)")
            if !p.salutation.isEmpty { contextLines.append("Preferred salutation: \(p.salutation)") }
            if !p.closing.isEmpty    { contextLines.append("Preferred closing: \(p.closing)") }
            if !p.notes.isEmpty      { contextLines.append("Notes: \(p.notes)") }
        }
        let contextBlock = contextLines.isEmpty ? "" :
            "\n\n<CONTEXT>\n\(contextLines.joined(separator: "\n"))\n</CONTEXT>"

        return """
        The user wrote rough draft notes in \(langName). \
        Expand them into a complete, polished message. \
        Choose the most appropriate format (email, chat, note, etc.) from context.

        Rules:
        - Write in \(langName)
        - Infer and match the appropriate register and formality from context
        - Preserve ALL the user's intended meaning — do not add facts not implied in the notes
        - Output ONLY the final message, no explanations or preamble\(contextBlock)

        <DRAFT>\(safeText)</DRAFT>
        """
    }
}
