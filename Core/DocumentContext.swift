import Foundation

enum WritingStyle: String, Sendable {
    case formal
    case informal
    case academic
    case technical
    case neutral

    var promptEngineStyle: String {
        switch self {
        case .formal:    return "formale"
        case .informal:  return "informale"
        case .academic:  return "accademico"
        case .technical: return "tecnico"
        case .neutral:   return "equilibrato"
        }
    }
}

struct DocumentContext: Sendable {
    let style: WritingStyle
    let confidence: Double
    let appBundleID: String?
}

actor ContextStorage {
    static let shared = ContextStorage()
    private(set) var current: DocumentContext?

    func store(_ context: DocumentContext) { current = context }
    func clear() { current = nil }
}

struct ContextAnalyzer {

    static func analyze(surroundingText: String, appBundleID: String?, language: String) -> DocumentContext {
        let appSignal = styleFromBundleID(appBundleID)

        // App bundle ID with high confidence always wins — it's the strongest signal.
        if let (style, confidence) = appSignal, confidence >= 0.85 {
            return DocumentContext(style: style, confidence: confidence, appBundleID: appBundleID)
        }

        // Text analysis — returns style + dynamic confidence proportional to signal strength.
        let (textStyle, textConf) = styleFromText(surroundingText, language: language)

        if let (appStyle, appConf) = appSignal {
            // Blend app signal and text signal. If they agree, boost confidence.
            if appStyle == textStyle {
                let blended = min(1.0, appConf * 0.6 + textConf * 0.4 + 0.1)
                return DocumentContext(style: appStyle, confidence: blended, appBundleID: appBundleID)
            }
            // Disagree: pick whichever has higher confidence, but cap at moderate certainty.
            let (winner, winnerConf) = appConf >= textConf ? (appStyle, appConf) : (textStyle, textConf)
            return DocumentContext(style: winner, confidence: min(0.75, winnerConf), appBundleID: appBundleID)
        }

        return DocumentContext(style: textStyle, confidence: textConf, appBundleID: appBundleID)
    }

    // MARK: - App Bundle ID Signal

    private static func styleFromBundleID(_ bundleID: String?) -> (WritingStyle, Double)? {
        guard let id = bundleID?.lowercased() else { return nil }
        let rules: [(String, WritingStyle, Double)] = [
            // Chat / messaging — strongly informal
            ("slack",           .informal, 0.92),
            ("discord",         .informal, 0.92),
            ("telegram",        .informal, 0.90),
            ("whatsapp",        .informal, 0.92),
            ("ichat",           .informal, 0.92),
            ("mobilesms",       .informal, 0.92),
            ("beeper",          .informal, 0.88),
            ("signal",          .informal, 0.90),
            ("facetime",        .informal, 0.88),
            // Social media
            ("twitter",         .informal, 0.88),
            ("reddit",          .informal, 0.85),
            ("mastodon",        .informal, 0.85),
            ("instagram",       .informal, 0.88),
            ("tiktok",          .informal, 0.88),
            // IDEs / dev tools — technical
            ("xcode",           .technical, 0.94),
            ("vscode",          .technical, 0.94),
            ("code-oss",        .technical, 0.92),
            ("cursor",          .technical, 0.90),
            ("nova",            .technical, 0.88),
            ("bbedit",          .technical, 0.85),
            ("iterm",           .technical, 0.88),
            ("terminal",        .technical, 0.85),
            ("ghostty",         .technical, 0.85),
            ("warp",            .technical, 0.88),
            // Academic tools
            ("overleaf",        .academic, 0.94),
            ("zotero",          .academic, 0.90),
            ("paperpile",       .academic, 0.88),
            ("texshop",         .academic, 0.90),
            ("endnote",         .academic, 0.88),
            // Email — formal
            ("mail",            .formal, 0.82),
            ("outlook",         .formal, 0.85),
            ("spark",           .formal, 0.80),
            ("mimestream",      .formal, 0.80),
            ("airmail",         .formal, 0.80),
            // Word processors — mildly formal (users vary widely)
            ("word",            .formal, 0.65),
            ("pages",           .formal, 0.65),
            ("libreoffice",     .formal, 0.65),
            ("notion",          .neutral, 0.60),
        ]
        for (keyword, style, conf) in rules where id.contains(keyword) {
            return (style, conf)
        }
        return nil
    }

    // MARK: - Text Signal

    // Returns (style, confidence). Confidence is proportional to: number of signals
    // that agree, distance between the winning score and the runner-up, and text length.
    private static func styleFromText(_ text: String, language: String) -> (WritingStyle, Double) {
        // CJK: lexicon scoring is unreliable; sentence length is the only usable signal.
        guard LanguageFamily.family(for: language) != .cjk else {
            return (.neutral, 0.40)
        }

        let rawWords = text.split(separator: " ").map(String.init)
        let words = rawWords.map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
        let wordCount = max(words.count, 1)

        // Require a minimum text length for reliable scoring.
        // Below 15 words, only strong structural signals (emoji, all-lowercase, etc.) are trusted.
        let tooShort = wordCount < 15

        let scores = Lexicon.computeWordScores(words: words, rawWords: rawWords, text: text)

        // --- Extra signals ---

        // Emoji → strong informal indicator
        let emojiCount = text.unicodeScalars.filter { $0.properties.isEmoji && $0.value > 0x238C }.count
        let emojiBoost = Double(emojiCount) * 15.0

        // @mention or #hashtag → informal/social
        let mentionCount = text.components(separatedBy: " ")
            .filter { $0.hasPrefix("@") || $0.hasPrefix("#") }.count
        let mentionBoost = Double(mentionCount) * 12.0

        // All-lowercase (no sentence starts with capital) → informal
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let lowercaseStarts = sentences.filter { s in
            guard let first = s.first else { return false }
            return first.isLetter && first.isLowercase
        }.count
        let allLowercaseBoost: Double = (!sentences.isEmpty && lowercaseStarts == sentences.count && sentences.count > 1) ? 20.0 : 0.0

        // URL/code density → technical
        let urlCount = text.components(separatedBy: " ")
            .filter { $0.hasPrefix("http") || $0.hasPrefix("www.") || $0.contains("://") }.count
        let urlBoost = Double(urlCount) * 8.0

        // Backtick/code fence → technical
        let codeBoost: Double = text.contains("`") ? 15.0 : 0.0

        // Multiple question marks → conversational/informal
        let questionBoost = Double(text.filter { $0 == "?" }.count) * 4.0

        let informalScore = scores.informalScore + emojiBoost + mentionBoost + allLowercaseBoost + questionBoost
        let academicScore = scores.academicScore
        let technicalScore = scores.technicalScore + urlBoost + codeBoost

        // Sentence length → formal heuristic (long sentences = formal/academic)
        let avgWordsPerSentence = sentences.isEmpty ? 0.0 : Double(wordCount) / Double(sentences.count)
        let formalFromSentenceLength: Double = avgWordsPerSentence > 22 ? 12.0 : (avgWordsPerSentence > 16 ? 6.0 : 0.0)

        // --- Pick winner ---
        // Thresholds calibrated for normalized density scores.
        let winners: [(WritingStyle, Double)] = [
            (.informal,  informalScore),
            (.academic,  academicScore),
            (.technical, technicalScore),
            (.formal,    formalFromSentenceLength),
        ]
        let sorted = winners.sorted { $0.1 > $1.1 }
        let (bestStyle, bestScore) = sorted[0]
        let runnerUpScore = sorted[1].1

        // Thresholds: different styles have different "easy to detect" thresholds.
        let threshold: Double
        switch bestStyle {
        case .informal:  threshold = tooShort ? 15.0 : 8.0
        case .technical: threshold = tooShort ? 15.0 : 6.0
        case .academic:  threshold = tooShort ? 12.0 : 4.0
        case .formal:    threshold = 8.0
        case .neutral:   threshold = 0.0
        }

        guard bestScore >= threshold else {
            return (.neutral, 0.40)
        }

        // Confidence: how far ahead is the winner vs runner-up, scaled by text length.
        let margin = bestScore - runnerUpScore
        let lengthFactor = min(1.0, Double(wordCount) / 60.0)
        let rawConf = 0.50 + min(0.40, margin / 30.0) * lengthFactor
        let confidence = tooShort ? min(rawConf, 0.65) : rawConf

        return (bestStyle, confidence)
    }
}
