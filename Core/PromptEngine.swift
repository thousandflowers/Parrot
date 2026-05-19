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
        case .latin:  return latinFamilyInstruction
        case .cjk:    return cjkFamilyInstruction
        case .arabic: return "Preserve right-to-left text direction and Arabic punctuation. Check verb-subject agreement, correct use of broken plurals, and proper use of definite article (ال)."
        case .slavic: return "Pay attention to case declensions, verb aspect (perfective/imperfective), and gender agreement. Preserve all diacritical characters exactly (č, ć, š, ž, đ, ź, ń, ř, etc.)."
        case .nordic: return "Preserve special characters exactly (å, ä, ö, ø, æ, ð, þ). Check noun gender agreement and verb conjugation."
        }
    }

    private var latinFamilyInstruction: String {
        switch primaryLanguageCode {
        case "de": return "Pay attention to case declension (Nominativ, Akkusativ, Dativ, Genitiv), noun gender (der/die/das), verb-second word order (Verbzweitstellung), and separable verbs."
        case "es": return "Pay attention to ser vs. estar, subjunctive mood (subjuntivo), gender and number agreement (concordancia), and correct use of por vs. para."
        case "pt": return "Pay attention to ser vs. estar, subjunctive mood (subjuntivo), gender agreement, and correct use of accents."
        case "el": return "Pay attention to noun declension, verb conjugation, and correct use of accents (τόνοι)."
        case "nl": return "Pay attention to noun gender (de/het), verb conjugation, and word order in subordinate clauses."
        case "tr": return "Pay attention to vowel harmony (sesli uyumu), correct suffixes for cases, and verb conjugation."
        default:    return ""
        }
    }

    private var cjkFamilyInstruction: String {
        switch primaryLanguageCode {
        case "zh", "yue":
            return "Preserve full-width punctuation. Do not convert to ASCII. Fix: incorrect word collocations (搭配错误, e.g. 提高态度→端正态度), redundant words (赘余, e.g. 非常的→非常), misused measure words (量词), repeated characters, and sentence structure errors."
        case "ja":
            return "Preserve full-width punctuation and Japanese writing conventions. Fix: particle errors (助詞, e.g. が vs は, で vs に), incorrect verb conjugation (動詞活用), misused honorifics (敬語), and word order errors."
        case "ko":
            return "Preserve full-width punctuation and Korean writing conventions. Fix: particle errors (조사, e.g. 이/가 vs 은/는, 에서 vs 에), honorific level consistency (경어법), and verb conjugation."
        default:
            return "Preserve full-width punctuation. Do not convert to ASCII. Pay attention to correct measure words, particles, and aspect markers."
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

        var lines: [String] = []
        lines.append("Fix grammar, spelling, punctuation, and word choice errors only. Keep the original meaning and language. Output ONLY the corrected text in the SAME language as the input. Do NOT translate.")
        if let nativeLine = nativeLanguageInstruction { lines.append(nativeLine) }
        if !extra.isEmpty { lines.append(extra) }
        if !styleLine.isEmpty { lines.append(styleLine) }
        if !flagged.isEmpty {
            lines.append("Possibly misspelled words: \(flagged.joined(separator: ", ")).")
        }
        if let custom = customInstruction { lines.append(custom) }
        lines.append("")
        lines.append(fewShotExamples())
        lines.append("")
        lines.append("Input: \"\(safeText)\"")
        lines.append("Output:")

        return lines.joined(separator: "\n")
    }

    private var nativeLanguageInstruction: String? {
        switch primaryLanguageCode {
        case "zh", "yue": return "只输出修正后的中文文本。不要翻译。不要解释。"
        case "ja":         return "修正後の日本語テキストのみ出力してください。翻訳や説明は不要です。"
        case "ko":         return "수정된 한국어 텍스트만 출력하세요. 번역하거나 설명하지 마세요."
        case "ar":         return "أخرج النص العربي المصحح فقط. لا تترجم. لا تشرح."
        case "ru":         return "Выводи только исправленный русский текст. Не переводи. Не объясняй."
        case "de":         return "Gib nur den korrigierten deutschen Text aus. Nicht übersetzen. Nicht erklären."
        case "es":         return "Produce solo el texto corregido en español. No traduzcas. No expliques."
        case "fr":         return "Produis uniquement le texte corrigé en français. Ne traduis pas. N'explique pas."
        case "it":         return "Produce solo il testo corretto in italiano. Non tradurre. Non spiegare."
        default:           return nil
        }
    }

    private func fewShotExamples() -> String {
        switch primaryLanguageCode {
        case "it":
            return """
            Input: "Io andato al mercato ieri."
            Output: "Sono andato al mercato ieri."
            Input: "Li ragazzi gioca a calcio nel parco ogni giorni."
            Output: "I ragazzi giocano a calcio nel parco ogni giorno."
            Input: "È inutile che tu viene, tanto non cambia niente."
            Output: "È inutile che tu venga, tanto non cambia niente."
            """
        case "fr":
            return """
            Input: "Je suis allé à le magasin hier."
            Output: "Je suis allé au magasin hier."
            Input: "Il as mangé une pomme ce matin."
            Output: "Il a mangé une pomme ce matin."
            Input: "Elle est plus intelligente que moi, bien qu'elle a moins d'expérience."
            Output: "Elle est plus intelligente que moi, bien qu'elle ait moins d'expérience."
            """
        case "de":
            return """
            Input: "Ich habe den Buch gelesen."
            Output: "Ich habe das Buch gelesen."
            Input: "Er geht in die Schule jeden Tag."
            Output: "Er geht jeden Tag in die Schule."
            Input: "Wegen dem schlechten Wetter blieb er zuhause."
            Output: "Wegen des schlechten Wetters blieb er zuhause."
            """
        case "es":
            return """
            Input: "Ayer yo he comido una manzana."
            Output: "Ayer yo comí una manzana."
            Input: "El agua está muy fría y cristalina."
            Output: "El agua está muy fría y cristalina."
            Input: "Espero que vengas y traes algo de comer."
            Output: "Espero que vengas y traigas algo de comer."
            """
        case "pt":
            return """
            Input: "Eu fui ao mercado e comprei legumes frescos."
            Output: "Eu fui ao mercado e comprei legumes frescos."
            Input: "Ele foi no mercado ontem de manhã."
            Output: "Ele foi ao mercado ontem de manhã."
            Input: "Espero que ele venha e traz os documentos."
            Output: "Espero que ele venha e traga os documentos."
            """
        case "ru":
            return """
            Input: "Он ушёл в магазин и купить хлеб."
            Output: "Он ушёл в магазин и купил хлеб."
            Input: "Я хочу попить воды холодный."
            Output: "Я хочу попить холодной воды."
            Input: "Несмотря на дождь, мы пошли прогулка."
            Output: "Несмотря на дождь, мы пошли на прогулку."
            """
        case "pl":
            return """
            Input: "Wczoraj ja poszłem do sklep."
            Output: "Wczoraj poszedłem do sklepu."
            Input: "On kupił nowy samochód za dużo pieniędzy."
            Output: "On kupił nowy samochód za dużo pieniędzy."
            """
        case "zh", "yue":
            return """
            Input: "我非常的喜欢吃苹果。"
            Output: "我非常喜欢吃苹果。"
            Input: "他昨天去了商店买了一些东西买了。"
            Output: "他昨天去了商店买了一些东西。"
            Input: "我们要提高学习态度。"
            Output: "我们要端正学习态度。"
            Input: "她的成绩有了很大的提升和进步。"
            Output: "她的成绩有了很大的提升。"
            """
        case "ja":
            return """
            Input: "私が昨日学校に行きました。"
            Output: "私は昨日学校に行きました。"
            Input: "彼女が図書館で勉強をしています。"
            Output: "彼女は図書館で勉強をしています。"
            Input: "電車に乗って駅まで歩きました。"
            Output: "電車に乗って駅まで行きました。"
            """
        case "ko":
            return """
            Input: "나는 어제 학교에 갔어요."
            Output: "저는 어제 학교에 갔어요."
            Input: "그녀가 도서관에서 공부를 하고 있어요."
            Output: "그녀는 도서관에서 공부를 하고 있어요."
            Input: "저는 밥이 먹었습니다."
            Output: "저는 밥을 먹었습니다."
            """
        case "ar":
            return """
            Input: "ذهبت البنات إلى المدرسة وتعلم الدرس."
            Output: "ذهبت البنات إلى المدرسة وتعلّمن الدرس."
            Input: "الكتب الجديد على الطاولة."
            Output: "الكتب الجديدة على الطاولة."
            """
        case "nl":
            return """
            Input: "Hij heeft gisteren de boek gelezen."
            Output: "Hij heeft gisteren het boek gelezen."
            Input: "Ze gaat naar de school elke dag."
            Output: "Ze gaat elke dag naar school."
            """
        case "sv":
            return """
            Input: "Han gick till affären och köpte en bröd."
            Output: "Han gick till affären och köpte ett bröd."
            Input: "Hon läser boken varje dagar."
            Output: "Hon läser boken varje dag."
            """
        case "tr":
            return """
            Input: "Ben okula gittim ve ders çalıştı."
            Output: "Ben okula gittim ve ders çalıştım."
            Input: "O kitabı okudum ve çok güzeldim."
            Output: "O kitabı okudum ve çok güzeldi."
            """
        default:
            return """
            Input: "He go to the store yesterday."
            Output: "He went to the store yesterday."
            Input: "The cats is sleeping on the couch since morning."
            Output: "The cats have been sleeping on the couch since morning."
            """
        }
    }

    func buildFluencyPrompt(for text: String, customInstruction: String? = nil) -> String {
        let styleLine = styleInstruction
        let safeText = escapeForPrompt(text)
        var lines: [String] = []
        lines.append("Rewrite the text to improve readability, flow, and naturalness. Combine short choppy sentences. Use varied sentence structure. Preserve the original meaning exactly. Output only the rewritten text.")
        if !styleLine.isEmpty { lines.append(styleLine) }
        if let custom = customInstruction { lines.append(custom) }
        lines.append("")

        switch primaryLanguageCode {
        case "it":
            lines.append("Input: \"Il progetto è finito. Il team ha festeggiato. È stato bello.\"")
            lines.append("Output: \"Al termine del progetto il team ha festeggiato — è stata un'esperienza gratificante.\"")
            lines.append("Input: \"Ho comprato il pane. Ho comprato il latte. Ho comprato le uova.\"")
            lines.append("Output: \"Ho fatto la spesa comprando pane, latte e uova.\"")
        case "fr":
            lines.append("Input: \"Le projet est terminé. L'équipe a fêté ça. C'était bien.\"")
            lines.append("Output: \"Une fois le projet terminé, l'équipe a célébré — une expérience enrichissante.\"")
        default:
            lines.append("Input: \"The project was completed. The team celebrated. It was good.\"")
            lines.append("Output: \"After completing the project, the team celebrated — it was a rewarding experience.\"")
            lines.append("Input: \"She went to the store. She bought milk. She came back home.\"")
            lines.append("Output: \"She went to the store, bought milk, and came back home.\"")
        }

        lines.append("")
        lines.append("Input: \"\(safeText)\"")
        lines.append("Output:")

        return lines.joined(separator: "\n")
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
        case "zh", "yue": return "Chinese"
        case "ja": return "Japanese"
        case "ar": return "Arabic"
        case "fa": return "Persian (Farsi)"
        case "he": return "Hebrew"
        case "ur": return "Urdu"
        case "hr": return "Croatian"
        case "cs": return "Czech"
        case "uk": return "Ukrainian"
        case "bg": return "Bulgarian"
        case "sr": return "Serbian"
        case "da": return "Danish"
        case "nb", "no": return "Norwegian"
        case "fi": return "Finnish"
        case "is": return "Icelandic"
        case "el": return "Greek"
        case "nl": return "Dutch"
        case "pl": return "Polish"
        case "sv": return "Swedish"
        case "ko": return "Korean"
        case "tr": return "Turkish"
        case "vi": return "Vietnamese"
        case "th": return "Thai"
        case "hi": return "Hindi"
        case "bn": return "Bengali"
        case "id": return "Indonesian"
        case "ms": return "Malay"
        case "ro": return "Romanian"
        case "hu": return "Hungarian"
        case "ca": return "Catalan"
        default:   return Locale.current.localizedString(forLanguageCode: code) ?? code
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
