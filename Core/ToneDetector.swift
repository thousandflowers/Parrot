import Foundation

enum DetectedTone: String, Sendable, CaseIterable {
    case formal
    case informal
    case neutral
    case academic
    case technical
}

actor ToneDetector {
    static let shared = ToneDetector()

    private lazy var passivePatternEN: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: "\\b(?:is|are|was|were|has been|have been|had been|will be|would be|should be|must be|being|been)\\s+\\w+(?:ed|en|t|d)\\b",
            options: [.caseInsensitive])
    }()
    private lazy var passivePatternIT: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: "\\b(?:è|sono|era|erano|fu|furono|sarà|saranno|sia|siano|fosse|fossero|viene|vengono|veniva|venivano|è stato|sono stati|era stato|erano stati)\\s+\\w+(?:ato|uto|ito|to|so|tto)\\b",
            options: [.caseInsensitive])
    }()
    private lazy var passivePatternFR: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: "\\b(?:est|sont|était|étaient|sera|seront|soit|soient|fût|fussent|a été|ont été|avait été|avaient été)\\s+\\w+(?:é|ée|és|ées|i|ie|is|ies|u|ue|us|ues)\\b",
            options: [.caseInsensitive])
    }()
    private lazy var passivePatternDE: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: "\\b(?:wird|werden|wurde|wurden|worden|worden ist|worden sind|wird|würde|würden)\\s+\\w+(?:t|en)\\b",
            options: [.caseInsensitive])
    }()
    private lazy var camelCasePattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\\b[A-Z][a-z]+(?:[A-Z][a-z]+)+\\b")
    }()

    func detect(text: String, language: String) -> DetectedTone {
        guard LanguageFamily.family(for: language) != .cjk else { return .neutral }

        let rawWords = text.split(separator: " ").map(String.init)
        let words = rawWords.map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
        let wordCount = max(words.count, 1)
        let lang = language.split(separator: "-").first.map(String.init) ?? language

        let scores = Lexicon.computeWordScores(
            words: words,
            rawWords: rawWords,
            text: text
        )

        // --- Contraction detection (language-specific) ---
        let contractions: Set<String>
        switch lang {
        case "it": contractions = Lexicon.informalContractionsIT
        case "fr": contractions = Lexicon.informalContractionsFR
        case "de": contractions = Lexicon.informalContractionsDE
        case "es": contractions = Lexicon.informalContractionsES
        case "pt": contractions = Lexicon.informalContractionsPT
        default:   contractions = Lexicon.informalContractionsEN
        }
        let contractionCount = rawWords.map({ $0.lowercased() }).filter { w in
            contractions.contains { w.hasPrefix($0) }
        }.count

        // --- Emoji / symbol signals ---
        let emojiCount = text.unicodeScalars.filter { $0.properties.isEmoji && $0.value > 0x238C }.count
        let mentionCount = text.components(separatedBy: " ")
            .filter { $0.hasPrefix("@") || $0.hasPrefix("#") }.count

        // --- All-lowercase check ---
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let lowercaseStarts = sentences.filter { s in
            guard let first = s.first else { return false }
            return first.isLetter && first.isLowercase
        }.count
        let allLowercaseBoost: Double = (sentences.count > 1 && lowercaseStarts == sentences.count) ? 20.0 : 0.0

        // --- Code / technical signals ---
        let codeBoost: Double = text.contains("`") || text.contains("```") ? 20.0 : 0.0
        let urlCount = text.components(separatedBy: " ")
            .filter { $0.hasPrefix("http") || $0.contains("://") }.count

        // --- Passive voice (language-specific) ---
        let passivePattern: NSRegularExpression?
        switch lang {
        case "it": passivePattern = passivePatternIT
        case "fr": passivePattern = passivePatternFR
        case "de": passivePattern = passivePatternDE
        default:   passivePattern = passivePatternEN
        }
        let passiveCount = passivePattern?.numberOfMatches(
            in: text, range: NSRange(location: 0, length: text.utf16.count)
        ) ?? 0

        let camelCaseCount = camelCasePattern?.numberOfMatches(
            in: text, range: NSRange(location: 0, length: text.utf16.count)
        ) ?? 0
        let longWordCount = words.filter { $0.count > 12 }.count

        // --- Compose scores ---
        let adjustedInformalScore = scores.informalScore
            + Double(contractionCount) / Double(wordCount) * 100.0
            + Double(emojiCount) * 15.0
            + Double(mentionCount) * 12.0
            + allLowercaseBoost

        let formalScore = Double(passiveCount) / Double(wordCount) * 100.0

        let adjustedTechnicalScore = scores.technicalScore
            + Double(camelCaseCount + longWordCount) / Double(wordCount) * 100.0
            + codeBoost
            + Double(urlCount) * 8.0

        // --- Thresholds ---
        // Require more evidence for short texts to avoid false positives.
        let shortText = wordCount < 12
        if adjustedInformalScore > (shortText ? 18.0 : 12.0) { return .informal }
        if scores.academicScore    > (shortText ? 8.0  : 5.0)  { return .academic }
        if formalScore             > (shortText ? 12.0 : 8.0)  { return .formal }
        if adjustedTechnicalScore  > (shortText ? 10.0 : 5.0)  { return .technical }
        return .neutral
    }
}
