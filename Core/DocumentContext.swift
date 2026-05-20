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

        if let (style, confidence) = appSignal, confidence >= 0.85 {
            return DocumentContext(style: style, confidence: confidence, appBundleID: appBundleID)
        }

        let textStyle = styleFromText(surroundingText, language: language)

        if let (appStyle, appConf) = appSignal {
            let boosted = appStyle == textStyle ? min(1.0, appConf + 0.1) : appConf
            return DocumentContext(style: appStyle, confidence: boosted, appBundleID: appBundleID)
        }

        return DocumentContext(style: textStyle, confidence: 0.6, appBundleID: appBundleID)
    }

    private static func styleFromBundleID(_ bundleID: String?) -> (WritingStyle, Double)? {
        guard let id = bundleID?.lowercased() else { return nil }
        let rules: [(String, WritingStyle, Double)] = [
            ("slack",       .informal, 0.90),
            ("discord",     .informal, 0.90),
            ("telegram",    .informal, 0.88),
            ("whatsapp",    .informal, 0.90),
            ("ichat",       .informal, 0.90),   // macOS Messages
            ("mobilesms",   .informal, 0.90),   // iOS Messages
            ("beeper",      .informal, 0.88),
            ("twitter",     .informal, 0.85),
            ("reddit",      .informal, 0.82),
            ("xcode",    .technical, 0.92),
            ("vscode",   .technical, 0.92),
            ("code-oss", .technical, 0.90),
            ("cursor",   .technical, 0.88),
            ("nova",     .technical, 0.85),
            ("bbedit",   .technical, 0.82),
            ("overleaf", .academic, 0.92),
            ("zotero",   .academic, 0.88),
            ("mail",     .formal, 0.78),
            ("outlook",  .formal, 0.82),
            ("spark",    .formal, 0.78),
            ("mimestream", .formal, 0.78),
            ("airmail",  .formal, 0.78),
            ("word",     .formal, 0.62),
            ("pages",    .formal, 0.62),
        ]
        for (keyword, style, conf) in rules where id.contains(keyword) {
            return (style, conf)
        }
        return nil
    }

    private static func styleFromText(_ text: String, language: String) -> WritingStyle {
        guard LanguageFamily.family(for: language) != .cjk else { return .neutral }

        let words = text.split(separator: " ")
            .map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
        let scores = Lexicon.computeWordScores(
            words: words,
            rawWords: words,
            text: text
        )

        if scores.informalScore > 8 { return .informal }
        if scores.academicScore > 5 { return .academic }
        if scores.technicalScore > 8 { return .technical }

        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let avgLen = sentences.isEmpty ? 0.0 : Double(scores.wordCount) / Double(sentences.count)
        if avgLen > 20 { return .formal }

        return .neutral
    }
}
