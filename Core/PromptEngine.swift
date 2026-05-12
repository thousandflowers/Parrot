import Foundation
import os
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

    enum CheckType: String, Codable, CaseIterable {
        case grammar
        case fluency
        case custom
    }

    init(id: UUID = UUID(), name: String, template: String, checkType: CheckType = .custom) {
        self.id = id
        self.name = name
        self.template = template
        self.checkType = checkType
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

    private func preCheckSpelling(_ text: String) -> (corrected: String, flagged: [String]) {
        let spellChecker = NSSpellChecker.shared
        let words = text.split(separator: " ")
        var corrected = text
        var flagged: [String] = []

        for word in words {
            let wordStr = String(word)
            let trimmed = wordStr.trimmingCharacters(in: .punctuationCharacters)
            guard trimmed.count > 2 else { continue }
            guard !IgnoreList.isIgnored(trimmed) else { continue }

            let range = spellChecker.checkSpelling(of: wordStr, startingAt: 0,
                language: language.starts(with: "en") ? "en" : language,
                wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)

            if range.location == NSNotFound { continue }

            guard let guesses = spellChecker.guesses(forWordRange: NSRange(location: 0, length: wordStr.utf16.count),
                in: wordStr, language: language.starts(with: "en") ? "en" : language,
                inSpellDocumentWithTag: 0), !guesses.isEmpty else { continue }

            if guesses.count == 1, guesses[0].lowercased() != wordStr.lowercased() {
                corrected = corrected.replacingOccurrences(of: wordStr, with: guesses[0])
            } else if guesses.count > 1 {
                flagged.append(wordStr)
            }
        }

        return (corrected, flagged)
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

        let (preChecked, flagged) = preCheckSpelling(text)
        let safeText = escapeForPrompt(preChecked)

        var header = "Fix only grammar/spelling for correctness; no style/fluency edits."
        if !extra.isEmpty { header += "\n\(extra)" }
        if !styleLine.isEmpty { header += "\n\(styleLine)" }
        if preChecked != text {
            header += "\nSome words were pre-corrected by spell check. Do not change them unless grammatically incorrect."
        }
        if !flagged.isEmpty {
            header += "\nPay special attention to these possibly misspelled words: \(flagged.joined(separator: ", "))"
        }
        header += "\n\nExample corrections:\n\(fewShotExamples())"

        return """
        \(header)

        <TEXT>\(safeText)</TEXT>\(customInstruction.map { "\n<CUSTOM>\($0)</CUSTOM>" } ?? "")

        Output only the corrected text; no notes. Do not include <TEXT>/<CUSTOM> tags.
        """
    }

    private func fewShotExamples() -> String {
        if language.starts(with: "it") {
            return "Input: \"Io andato al mercato ieri.\"\nOutput: \"Io sono andato al mercato ieri.\"\n\nInput: \"Li ragazzi gioca a calcio nel parco.\"\nOutput: \"I ragazzi giocano a calcio nel parco.\"\n\nInput: \"La mela e buona.\"\nOutput: \"La mela è buona.\""
        }
        return "Input: \"He go to the store yesterday.\"\nOutput: \"He went to the store yesterday.\"\n\nInput: \"The cats is sleeping on the couch.\"\nOutput: \"The cats are sleeping on the couch.\"\n\nInput: \"Their going to the park.\"\nOutput: \"They're going to the park.\""
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

        Output only the corrected text; no notes. Do not include <TEXT>/<CUSTOM> tags.
        """
    }

    func buildExplainPrompt(original: String, corrected: String, customInstruction: String? = nil) -> String {
        let styleLine = styleInstruction
        let safeOriginal = escapeForPrompt(original)
        let safeCorrected = escapeForPrompt(corrected)
        var header = "Explain the grammar, spelling, or style errors in the original text."
        header += "\nBe educational but concise."
        header += "\nExplain in \(language)."
        if !styleLine.isEmpty { header += "\n\(styleLine)" }
        return """
        \(header)

        Original:
        <TEXT>\(safeOriginal)</TEXT>
        Corrected:
        <TEXT>\(safeCorrected)</TEXT>\(customInstruction.map { "\n<CUSTOM>\($0)</CUSTOM>" } ?? "")

        Output only your explanation. Do not include <TEXT>/<CUSTOM> tags.
        """
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
