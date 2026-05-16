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

    private static let informalContractionsEN: Set<String> = [
        "don't", "can't", "it's", "we're", "i'm", "you're", "they're",
        "won't", "shouldn't", "couldn't", "wouldn't", "isn't", "aren't",
        "wasn't", "weren't", "hasn't", "haven't", "hadn't", "let's",
        "that's", "what's", "who's", "here's", "there's", "he's", "she's",
        "i'll", "you'll", "he'll", "she'll", "we'll", "they'll",
        "i've", "you've", "we've", "they've", "i'd", "you'd", "he'd", "she'd",
    ]

    private static let informalContractionsIT: Set<String> = [
        "dell'", "nell'", "sull'", "coll'", "all'", "dall'",
        "c'è", "c'era", "c'erano", "l'ho", "l'hai", "l'ha",
        "m'ha", "t'ho", "s'è", "n'è",
    ]

    private static let informalWords: Set<String> = [
        "hey", "yeah", "yep", "nope", "cool", "awesome", "gonna",
        "wanna", "gotta", "kinda", "sorta", "dunno", "lol", "omg",
        "btw", "thx", "pls", "ok", "okay", "nah", "wow", "oops",
        "ciao", "eh", "ah", "oh",
    ]

    private static let academicMarkers: Set<String> = [
        "therefore", "furthermore", "consequently", "nonetheless",
        "moreover", "thus", "hence", "accordingly", "nevertheless",
        "whereas", "hereby", "therein", "thereof", "wherein",
        "pertanto", "inoltre", "dunque", "conseguentemente",
        "ciononostante", "tuttavia", "perciò", "nonostante",
    ]

    private static let passivePatternEN: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: "\\b(?:is|are|was|were|has been|have been|had been|will be|would be|should be|must be|being|been)\\s+\\w+(?:ed|en|t|d)\\b",
            options: [.caseInsensitive]
        )
    }()

    private static let passivePatternIT: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: "\\b(?:è|sono|era|erano|fu|furono|sarà|saranno|sia|siano|fosse|fossero|viene|vengono|veniva|venivano|è stato|sono stati|era stato|erano stati)\\s+\\w+(?:ato|uto|ito|to|so|tto)\\b",
            options: [.caseInsensitive]
        )
    }()

    private static let camelCasePattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\\b[A-Z][a-z]+(?:[A-Z][a-z]+)+\\b")
    }()

    func detect(text: String, language: String) -> DetectedTone {
        let rawWords = text.split(separator: " ")
        let words = rawWords.map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
        let wordCount = max(words.count, 1)
        let isItalian = language.starts(with: "it")

        let contractions = isItalian ? Self.informalContractionsIT : Self.informalContractionsEN
        let contractionCount = words.filter { w in contractions.contains { w.hasPrefix($0) } }.count
        let informalWordCount = words.filter { Self.informalWords.contains($0) }.count
        let academicCount = words.filter { Self.academicMarkers.contains($0) }.count

        let exclamationCount = text.filter { $0 == "!" }.count
        let allCapsRatio: Double = {
            let capsWords = words.filter { $0 == $0.uppercased() && $0.count > 2 }
            return Double(capsWords.count) / Double(wordCount)
        }()

        let passivePattern = isItalian ? Self.passivePatternIT : Self.passivePatternEN
        let passiveCount = passivePattern?.numberOfMatches(
            in: text, range: NSRange(location: 0, length: text.utf16.count)
        ) ?? 0

        let techWordCount = Self.camelCasePattern?.numberOfMatches(
            in: text, range: NSRange(location: 0, length: text.utf16.count)
        ) ?? 0
        let longWordCount = words.filter { $0.count > 12 }.count

        let informalScore = Double(contractionCount + informalWordCount) / Double(wordCount) * 100.0
            + Double(exclamationCount) * 5.0
            + allCapsRatio * 50.0
        let formalScore = Double(passiveCount) / Double(wordCount) * 100.0
        let academicScore = Double(academicCount) / Double(wordCount) * 100.0
        let technicalScore = Double(techWordCount + longWordCount) / Double(wordCount) * 100.0

        if informalScore > 12.0 { return .informal }
        if academicScore > 5.0 { return .academic }
        if formalScore > 8.0 { return .formal }
        if technicalScore > 5.0 { return .technical }
        return .neutral
    }
}
