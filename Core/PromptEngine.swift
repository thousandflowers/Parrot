import Foundation

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

    func buildGrammarPrompt(for text: String, customInstruction: String? = nil) -> String {
        let extra = grammarFamilyInstruction
        return """
        Fix only grammar/spelling for correctness; no style/fluency edits.\(extra.isEmpty ? "" : "\n\(extra)")

        <TEXT>\(text)</TEXT>\(customInstruction.map { "\n<CUSTOM>\($0)</CUSTOM>" } ?? "")

        Output only the corrected text; no notes. Do not include <TEXT>/<CUSTOM> tags.
        """
    }

    func buildFluencyPrompt(for text: String, customInstruction: String? = nil) -> String {
        """
        Improve fluency and naturalness only; do not fix grammar already correct.

        <TEXT>\(text)</TEXT>\(customInstruction.map { "\n<CUSTOM>\($0)</CUSTOM>" } ?? "")

        Output only the corrected text; no notes. Do not include <TEXT>/<CUSTOM> tags.
        """
    }

    func buildExplainPrompt(original: String, corrected: String, customInstruction: String? = nil) -> String {
        """
        Explain the grammar, spelling, or style errors in the original text.
        Be educational but concise.
        Explain in \(language).

        Original:
        <TEXT>\(original)</TEXT>
        Corrected:
        <TEXT>\(corrected)</TEXT>\(customInstruction.map { "\n<CUSTOM>\($0)</CUSTOM>" } ?? "")

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
            fatalError("Use buildExplainPrompt(original:corrected:) directly — buildPrompt does not support explain")
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
