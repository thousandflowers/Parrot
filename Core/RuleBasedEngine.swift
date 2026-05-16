import Foundation

struct RuleBasedFix: Equatable, Sendable {
    let original: String
    let corrected: String
    let reason: String
}

struct RuleBasedResult: Sendable {
    let text: String
    let fixes: [RuleBasedFix]
    var hasFixes: Bool { !fixes.isEmpty }
}

typealias RegexReplacement = @Sendable (String) -> String

struct GrammarRule: Sendable {
    let id: String
    let pattern: String
    let options: NSRegularExpression.Options
    let replacement: RegexReplacement
    let reason: String
    let languages: Set<String>
    let isUniversal: Bool
}

actor RuleBasedEngine {
    static let shared = RuleBasedEngine()

    private let compiledRules: [(rule: GrammarRule, regex: NSRegularExpression)]

    init() {
        let rules = Self.makeRules()
        var compiled: [(GrammarRule, NSRegularExpression)] = []
        for rule in rules {
            if let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) {
                compiled.append((rule, regex))
            }
        }
        compiledRules = compiled
    }

    func check(_ text: String, language: String = "it") -> RuleBasedResult {
        var fixes: [RuleBasedFix] = []
        var result = text

        for (rule, regex) in compiledRules where rule.isUniversal || rule.languages.contains(language) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: range)

            for match in matches.reversed() {
                guard let swiftRange = Range(match.range, in: result) else { continue }
                let original = String(result[swiftRange])
                let replacement = rule.replacement(original)

                if original != replacement {
                    fixes.insert(RuleBasedFix(
                        original: original,
                        corrected: replacement,
                        reason: rule.reason
                    ), at: 0)
                    result.replaceSubrange(swiftRange, with: replacement)
                }
            }
        }

        return RuleBasedResult(text: result, fixes: fixes)
    }

    private static func makeRules() -> [GrammarRule] {
        [
            GrammarRule(
                id: "it-qual-e",
                pattern: "(?i)qual'è",
                options: [],
                replacement: { match in match.hasPrefix("Q") ? "Qual è" : "qual è" },
                reason: "«Qual è» si scrive senza apostrofo (troncamento, non elisione)",
                languages: ["it"],
                isUniversal: false
            ),
            GrammarRule(
                id: "it-un-po",
                pattern: "un pò",
                options: [],
                replacement: { _ in "un po'" },
                reason: "«Po'» è troncamento di «poco», vuole l'apostrofo non l'accento",
                languages: ["it"],
                isUniversal: false
            ),
            GrammarRule(
                id: "it-e-accento",
                pattern: "(?<![a-zA-Z])e'(?=\\s|[,.!?;:]|$)",
                options: [],
                replacement: { _ in "è" },
                reason: "«È» verbo vuole l'accento, non l'apostrofo",
                languages: ["it"],
                isUniversal: false
            ),
            GrammarRule(
                id: "it-ne-accento",
                pattern: "(?<![a-zA-Z])ne'(?=\\s|[,.!?;:]|$)",
                options: [],
                replacement: { _ in "né" },
                reason: "«Né» congiunzione vuole l'accento, non l'apostrofo",
                languages: ["it"],
                isUniversal: false
            ),
            GrammarRule(
                id: "it-se-accento",
                pattern: "(?<![a-zA-Z])se'(?=\\s|[,.!?;:]|$)",
                options: [],
                replacement: { _ in "sé" },
                reason: "«Sé» pronome vuole l'accento, non l'apostrofo",
                languages: ["it"],
                isUniversal: false
            ),
            GrammarRule(
                id: "it-da-accento",
                pattern: "(?<![a-zA-Z])da'(?=\\s|[,.!?;:]|$)",
                options: [],
                replacement: { _ in "dà" },
                reason: "«Dà» voce del verbo dare vuole l'accento",
                languages: ["it"],
                isUniversal: false
            ),
            GrammarRule(
                id: "it-li-accento",
                pattern: "(?<![a-zA-Z])li'(?=\\s|[,.!?;:]|$)",
                options: [],
                replacement: { _ in "lì" },
                reason: "«Lì» avverbio vuole l'accento, non l'apostrofo",
                languages: ["it"],
                isUniversal: false
            ),
            GrammarRule(
                id: "it-la-accento",
                pattern: "(?<![a-zA-Z])la'(?=\\s|[,.!?;:]|$)",
                options: [],
                replacement: { _ in "là" },
                reason: "«Là» avverbio vuole l'accento, non l'apostrofo",
                languages: ["it"],
                isUniversal: false
            ),
            GrammarRule(
                id: "it-si-accento",
                pattern: "(?<![a-zA-Z])si'(?=\\s|[,.!?;:]|$)",
                options: [],
                replacement: { _ in "sì" },
                reason: "«Sì» affermativo vuole l'accento, non l'apostrofo",
                languages: ["it"],
                isUniversal: false
            ),
            GrammarRule(
                id: "double-space",
                pattern: "  +",
                options: [],
                replacement: { _ in " " },
                reason: "Spazio doppio",
                languages: [],
                isUniversal: true
            ),
            GrammarRule(
                id: "space-before-punctuation",
                pattern: "\\s+([,.!?;:])",
                options: [],
                replacement: { match in
                    if let range = match.range(of: "[,.!?;:]", options: .regularExpression) {
                        return String(match[range])
                    }
                    return match
                },
                reason: "Niente spazio prima della punteggiatura",
                languages: [],
                isUniversal: true
            ),
            GrammarRule(
                id: "en-their-theyre",
                pattern: "(?i)\\btheir\\b(?=\\s+(?:going|coming|running|walking|doing|making|trying|looking|working|playing|saying|thinking|getting|giving|taking|leaving|putting|bringing|asking|helping|talking|turning|starting|showing|moving|living|believing|holding|writing|providing|sitting|standing|losing|paying|meeting|including|continuing|setting|learning|leading|understanding|watching|following|creating|speaking|spending|growing|opening|winning|teaching|offering|remembering|considering|appearing|buying|serving|achieving|dying|developing|sending|building|staying|falling|cutting|reaching|killing|remaining|suggesting|raising|passing|selling|requiring|reporting|deciding|pulling))",
                options: [],
                replacement: { match in match.hasPrefix("T") ? "They're" : "they're" },
                reason: "«They're» = they are; «their» = possessivo",
                languages: ["en"],
                isUniversal: false
            ),
            GrammarRule(
                id: "en-your-vs-youre",
                pattern: "(?i)\\byour\\b(?=\\s+(?:welcome|right|wrong|absolutely|correct|kidding|joking|being|doing|going|coming|looking|trying|making|very))",
                options: [],
                replacement: { match in
                    match.hasPrefix("Y") && match.hasPrefix("Your") ? "You're" : "you're"
                },
                reason: "«You're» = you are; «your» = possessivo",
                languages: ["en"],
                isUniversal: false
            ),
        ]
    }
}
