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
        case "it": return "Fix verb conjugation errors (wrong auxiliary essere/avere, wrong person or number), subject-verb agreement, and article agreement (un/uno, il/lo, i/gli) when clearly wrong. In subordinate clauses after 'che' following verbs of opinion, belief, or wish (pensare, credere, sperare, volere, preferire, temere, etc.), congiuntivo is required — replace ANY wrong word, including pronouns and non-verbs, with the correct congiuntivo form (e.g. 'penso che me alto' → 'penso che sia alto'; 'penso che lui è' → 'penso che lui sia'; 'È inutile che tu viene' → 'È inutile che tu venga'). Do NOT replace one tense with another when both are grammatically valid in context (e.g., do not swap imperfetto for passato prossimo)."
        case "de": return "Fix verb conjugation errors, case declension, and article errors (der/die/das/dem/den/des) when clearly wrong. Do NOT replace one tense with another when both are valid (Präteritum/Perfekt/Plusquamperfekt). Do NOT change Konjunktiv II unless syntax demands it."
        case "es": return "Fix verb conjugation, ser/estar usage, and agreement errors when clearly wrong. Do NOT replace one tense with another when both are valid (e.g., indefinido vs imperfecto). Do NOT change subjuntivo mood unless syntax demands a different mood."
        case "fr": return "Fix verb conjugation, agreement, and article contraction errors when clearly wrong. Do NOT replace one tense with another when both are valid (e.g., imparfait vs passé composé). Do NOT change subjonctif mood unless syntax demands it."
        case "pt": return "Fix verb conjugation, ser/estar usage, and agreement errors when clearly wrong. Do NOT replace one tense with another when both are valid. Do NOT change subjuntivo mood unless syntax demands it."
        case "el": return "Pay attention to noun declension, verb conjugation, and correct use of accents (τόνοι). Do NOT change tense choice when both options are valid."
        case "nl": return "Fix noun gender (de/het) and verb conjugation errors when clearly wrong. Do NOT change tense or word order in subordinate clauses unless grammatically incorrect."
        case "tr": return "Fix vowel harmony (sesli uyumu), case suffix errors, and verb conjugation when clearly wrong. Do NOT change tense or aspect unless clearly incorrect."
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
        let examples = fewShotExamples()

        var parts: [String] = []
        parts.append("Fix all grammatical errors in the text inside <TEXT>: misspellings, wrong verb forms, wrong agreement, and broken phrases where the words as written are syntactically impossible. You may add or replace words ONLY to fix a clear grammatical error — for example, add a missing verb form or replace a wrong form. Do not rephrase correct sentences, do not reorder, do not substitute synonyms. Return only the corrected text.")
        if !extra.isEmpty { parts.append(extra) }
        if !styleLine.isEmpty { parts.append(styleLine) }
        if let custom = customInstruction { parts.append(custom) }
        if let styleHint = StyleProfiler.buildHint(language: language) { parts.append(styleHint) }
        if !examples.isEmpty { parts.append("\nExamples:\n\(examples)") }
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
            Input: "Maria è andato al lavoro stamattina."
            Output: "Maria è andata al lavoro stamattina."
            Input: "Devo di comprare il pane oggi."
            Output: "Devo comprare il pane oggi."
            Input: "Ho messo un zaino in macchina."
            Output: "Ho messo uno zaino in macchina."
            Input: "Il studente legge il libro."
            Output: "Lo studente legge il libro."
            Input: "La ragazza era andata via prima che arrivassimo."
            Output: "La ragazza era andata via prima che arrivassimo."
            Input: "Se avessi saputo, sarei venuta prima."
            Output: "Se avessi saputo, sarei venuta prima."
            """
        case "fr":
            return """
            Input: "Je suis allé à le magasin hier."
            Output: "Je suis allé au magasin hier."
            Input: "Il as mangé une pomme ce matin."
            Output: "Il a mangé une pomme ce matin."
            Input: "Elle est plus intelligente que moi, bien qu'elle a moins d'expérience."
            Output: "Elle est plus intelligente que moi, bien qu'elle ait moins d'expérience."
            Input: "J'ai acheté de le pain ce matin."
            Output: "J'ai acheté du pain ce matin."
            Input: "Elle était partie avant que nous arrivions."
            Output: "Elle était partie avant que nous arrivions."
            Input: "Si j'avais su, je serais venue plus tôt."
            Output: "Si j'avais su, je serais venue plus tôt."
            """
        case "de":
            return """
            Input: "Ich habe den Buch gelesen."
            Output: "Ich habe das Buch gelesen."
            Input: "Er geht in die Schule jeden Tag."
            Output: "Er geht jeden Tag in die Schule."
            Input: "Wegen dem schlechten Wetter blieb er zuhause."
            Output: "Wegen des schlechten Wetters blieb er zuhause."
            Input: "Sie hatte das Haus verlassen, bevor er ankam."
            Output: "Sie hatte das Haus verlassen, bevor er ankam."
            Input: "Wenn ich das gewusst hätte, wäre ich früher gekommen."
            Output: "Wenn ich das gewusst hätte, wäre ich früher gekommen."
            """
        case "es":
            return """
            Input: "Ayer yo he comido una manzana."
            Output: "Ayer yo comí una manzana."
            Input: "El agua está muy fría y cristalina."
            Output: "El agua está muy fría y cristalina."
            Input: "Espero que vengas y traes algo de comer."
            Output: "Espero que vengas y traigas algo de comer."
            Input: "Ella había llegado antes de que nosotros llegáramos."
            Output: "Ella había llegado antes de que nosotros llegáramos."
            Input: "Si lo hubiera sabido, habría venido antes."
            Output: "Si lo hubiera sabido, habría venido antes."
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
            Input: "She is a honest person."
            Output: "She is an honest person."
            Input: "The cats is sleeping on the couch since morning."
            Output: "The cats have been sleeping on the couch since morning."
            """
        }
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
        let langName = englishLanguageName(for: language)
        var instruction = "Explain the grammar, spelling, or style errors corrected in this text. Be concise. Explain in \(langName)."
        if !styleLine.isEmpty { instruction += " \(styleLine)" }
        if let custom = customInstruction { instruction += " \(custom)" }
        let safeOriginal = escapeForPrompt(original)
        let safeCorrected = escapeForPrompt(corrected)
        return "\(instruction)\n\nORIGINAL: \(safeOriginal)\nCORRECTED: \(safeCorrected)"
    }

    func buildCoachPrompt(for text: String) -> String {
        let langName = englishLanguageName(for: language)
        let safeText = escapeForPrompt(text)
        return """
        You are a writing coach. Respond in \(langName). Look at the text below and list only the real issues you can see in it — grammar errors, unclear phrasing, awkward word choices. For each issue: quote the exact problematic part, explain what is wrong, and give a corrected version. If there are no significant issues, say so briefly. Do not invent issues that are not in the text.

        <TEXT>\(safeText)</TEXT>
        """
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
            return buildExpandPrompt(for: text, messageType: nil, recipient: nil, contactProfile: nil)
        }
    }

    func buildDeSlopPrompt(for text: String) -> String {
        let safeText = escapeForPrompt(text)
        let langName = englishLanguageName(for: language)
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

    func buildExpandPrompt(
        for text: String,
        messageType: DraftDetector.MessageType?,
        recipient: String?,
        contactProfile: ContactProfile?
    ) -> String {
        let safeText = escapeForPrompt(text)
        let langName = englishLanguageName(for: language)

        var contextLines: [String] = []

        if let profile = contactProfile {
            contextLines.append("Recipient: \(profile.name)")
            if !profile.role.isEmpty { contextLines.append("Role: \(profile.role)") }
            contextLines.append("Formality: \(profile.formality.rawValue)")
            contextLines.append("Preferred salutation: \(profile.salutation)")
            contextLines.append("Preferred closing: \(profile.closing)")
            if !profile.notes.isEmpty { contextLines.append("Notes: \(profile.notes)") }
        } else if let recipient {
            contextLines.append("Likely recipient role: \(recipient)")
        }

        let msgTypeNote: String
        switch messageType ?? .generic {
        case .email:
            msgTypeNote = "Format as a complete, polite email (salutation, body paragraphs, closing)."
        case .chat:
            msgTypeNote = "Format as a concise, appropriately-toned chat message."
        case .generic:
            msgTypeNote = "Format as a complete, well-structured message appropriate to the context."
        }

        let contextBlock = contextLines.isEmpty ? "" :
            "\n\n<CONTEXT>\n\(contextLines.joined(separator: "\n"))\n</CONTEXT>"

        return """
        The user has written rough draft notes in \(langName). Expand them into a complete, polished message.
        \(msgTypeNote)

        Rules:
        - Write in \(langName)
        - Match the formality to the recipient context
        - Preserve ALL the user's intended meaning and facts
        - Do NOT add information that was not implied in the notes
        - Output ONLY the final message, no explanations\(contextBlock)

        <DRAFT>\(safeText)</DRAFT>
        """
    }
}
