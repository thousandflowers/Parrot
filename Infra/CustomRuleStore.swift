import Foundation

actor CustomRuleStore {
    static let shared = CustomRuleStore()

    private var rules: [CustomRule] = []
    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("RefineClone")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        fileURL = appSupport.appendingPathComponent("custom_rules.json")
        loadSync()
    }

    func allRules() -> [CustomRule] { rules }

    func add(_ rule: CustomRule) {
        rules.append(rule)
        save()
    }

    func update(_ rule: CustomRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        save()
    }

    func remove(id: UUID) {
        rules.removeAll { $0.id == id }
        save()
    }

    func apply(to text: String, language: String) -> (text: String, fixes: [CustomRuleFix]) {
        var result = text
        var fixes: [CustomRuleFix] = []

        for rule in rules where rule.isEnabled {
            if rule.language != "any" && rule.language != language { continue }

            if rule.isRegex {
                do {
                    let regex = try NSRegularExpression(
                        pattern: rule.pattern,
                        options: rule.isCaseSensitive ? [] : .caseInsensitive
                    )
                    let nsRange = NSRange(result.startIndex..., in: result)
                    let matches = regex.matches(in: result, options: [], range: nsRange)

                    for match in matches.reversed() {
                        guard let range = Range(match.range, in: result) else { continue }
                        let original = String(result[range])
                        let replaced = regex.stringByReplacingMatches(
                            in: result, options: [], range: match.range,
                            withTemplate: rule.replacement
                        )
                        fixes.append(CustomRuleFix(ruleName: rule.name, original: original, corrected: String(replaced[Range(match.range, in: replaced)!])))
                        result = replaced
                    }
                } catch {
                    continue
                }
            } else {
                let options: String.CompareOptions = rule.isCaseSensitive ? [] : [.caseInsensitive]
                var searchStart = result.startIndex
                while let range = result.range(of: rule.pattern, options: options, range: searchStart..<result.endIndex) {
                    let original = String(result[range])
                    result.replaceSubrange(range, with: rule.replacement)
                    fixes.append(CustomRuleFix(ruleName: rule.name, original: original, corrected: rule.replacement))
                    searchStart = result.index(range.lowerBound, offsetBy: rule.replacement.count)
                    if searchStart >= result.endIndex { break }
                }
            }
        }

        return (result, fixes)
    }

    private func loadSync() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([CustomRule].self, from: data) else {
            return
        }
        rules = decoded
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([CustomRule].self, from: data) else {
            return
        }
        rules = decoded
    }

    private func save() {
        try? JSONEncoder().encode(rules).write(to: fileURL)
    }
}

struct CustomRuleFix: Sendable {
    let ruleName: String
    let original: String
    let corrected: String
}
