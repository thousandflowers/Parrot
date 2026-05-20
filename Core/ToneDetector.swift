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
        try? NSRegularExpression(pattern: "\\b(?:is|are|was|were|has been|have been|had been|will be|would be|should be|must be|being|been)\\s+\\w+(?:ed|en|t|d)\\b", options: [.caseInsensitive])
    }()
    private lazy var passivePatternIT: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\\b(?:è|sono|era|erano|fu|furono|sarà|saranno|sia|siano|fosse|fossero|viene|vengono|veniva|venivano|è stato|sono stati|era stato|erano stati)\\s+\\w+(?:ato|uto|ito|to|so|tto)\\b", options: [.caseInsensitive])
    }()
    private lazy var camelCasePattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\\b[A-Z][a-z]+(?:[A-Z][a-z]+)+\\b")
    }()

    func detect(text: String, language: String) -> DetectedTone {
        guard LanguageFamily.family(for: language) != .cjk else { return .neutral }

        let rawWords = text.split(separator: " ")
        let words = rawWords.map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
        let isItalian = language.starts(with: "it")

        let scores = Lexicon.computeWordScores(
            words: words,
            rawWords: rawWords.map(String.init),
            text: text
        )

        let contractions: Set<String> = isItalian
            ? Lexicon.informalContractionsIT
            : Lexicon.informalContractionsEN
        let contractionCount = rawWords.map({ $0.lowercased() }).filter { w in
            contractions.contains { w.hasPrefix($0) }
        }.count

        let adjustedInformalScore = scores.informalScore
            + Double(contractionCount) / Double(scores.wordCount) * 100.0

        let passivePattern = isItalian ? passivePatternIT : passivePatternEN
        let passiveCount = passivePattern?.numberOfMatches(
            in: text, range: NSRange(location: 0, length: text.utf16.count)
        ) ?? 0
        let techWordCount = camelCasePattern?.numberOfMatches(
            in: text, range: NSRange(location: 0, length: text.utf16.count)
        ) ?? 0
        let longWordCount = words.filter { $0.count > 12 }.count

        let formalScore = Double(passiveCount) / Double(scores.wordCount) * 100.0
        let technicalScore = (Double(techWordCount + longWordCount)) / Double(scores.wordCount) * 100.0

        if adjustedInformalScore > 12.0 { return .informal }
        if scores.academicScore > 5.0 { return .academic }
        if formalScore > 8.0 { return .formal }
        if technicalScore > 5.0 { return .technical }
        return .neutral
    }
}
