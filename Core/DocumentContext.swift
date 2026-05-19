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
        // CJK text can't be reliably tokenised by space; defer to app bundle signal
        guard LanguageFamily.family(for: language) != .cjk else { return .neutral }

        let words = text.split(separator: " ")
            .map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
        let wordCount = max(words.count, 1)

        let informalWords: Set<String> = [
            "hey", "yeah", "yep", "nope", "cool", "awesome", "gonna", "wanna", "gotta",
            "kinda", "sorta", "dunno", "lol", "omg", "btw", "thx", "ok", "okay", "nah",
            "ciao", "eh", "xd", "haha", "lmao", "rofl", "tbh", "imo", "smh",
            // French
            "ouais", "nan", "bah", "hein", "genre", "truc", "machin", "chelou",
            "ouf", "grave", "carrément", "trop", "vachement",
            // Croatian
            "bok", "cao", "kul", "hej", "jel", "šta", "kaj",
            // Danish
            "fedt", "nice", "sejt", "bare", "altså",
        ]
        let academicWords: Set<String> = [
            "therefore", "furthermore", "consequently", "nonetheless", "moreover",
            "thus", "hence", "accordingly", "nevertheless", "whereas", "pertanto",
            "inoltre", "dunque", "conseguentemente", "ciononostante", "tuttavia",
            "altresì", "parimenti", "nonostante",
            // French
            "ainsi", "néanmoins", "cependant", "toutefois", "certes",
            "par conséquent", "en outre",
            // Croatian
            "stoga", "međutim", "naime", "štoviše", "naposljetku",
            // Danish
            "desuden", "endvidere", "følgelig", "imidlertid", "ligeledes",
        ]
        let technicalWords: Set<String> = [
            "function", "variable", "api", "json", "http", "async",
            "import", "struct", "protocol", "interface", "const",
            "swift", "python", "javascript", "typescript", "kotlin",
            "boolean", "integer", "callback", "endpoint", "repository",
            "dockerfile", "kubernetes", "docker", "gradle", "webpack",
        ]

        let informalCount = words.filter { informalWords.contains($0) }.count
        let academicCount = words.filter { academicWords.contains($0) }.count
        let technicalCount = words.filter { technicalWords.contains($0) }.count

        let exclamationCount = text.filter { $0 == "!" }.count
        let semicolonCount = text.filter { $0 == ";" }.count

        let informalScore  = Double(informalCount)  / Double(wordCount) * 100 + Double(exclamationCount) * 3
        let academicScore  = Double(academicCount)  / Double(wordCount) * 100 + Double(semicolonCount)
        let technicalScore = Double(technicalCount) / Double(wordCount) * 100

        if informalScore  > 8 { return .informal }
        if academicScore  > 5 { return .academic }
        if technicalScore > 8 { return .technical }

        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let avgLen = sentences.isEmpty ? 0.0 : Double(wordCount) / Double(sentences.count)
        if avgLen > 20 { return .formal }

        return .neutral
    }
}
