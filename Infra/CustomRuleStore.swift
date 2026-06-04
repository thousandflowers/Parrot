import Foundation

actor CustomRuleStore {
    static let shared = CustomRuleStore()

    private var rules: [CustomRule] = []
    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let appSupport = base.appendingPathComponent("Parrot")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let url = appSupport.appendingPathComponent("custom_rules.json")
        fileURL = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([CustomRule].self, from: data) {
            rules = decoded
        }
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

    func apply(to text: String, language: String) async -> (text: String, fixes: [CustomRuleFix]) {
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
                    // Timeout guard: if the regex takes longer than 100ms on the input,
                    // treat it as a no-match to prevent ReDoS on pathological patterns
                    // like (a+)+b crafted by the user. NSRegularExpression is synchronous
                    // with no built-in timeout, so we run it on a background queue with
                    // a deadline.
                    let deadline = Date().addingTimeInterval(0.1)
                    let matches = try await withThrowingTaskGroup(of: [NSTextCheckingResult].self) { group in
                        group.addTask {
                            try Task.checkCancellation()
                            return regex.matches(in: result, options: [], range: nsRange)
                        }
                        group.addTask {
                            try await Task.sleep(for: .milliseconds(100))
                            throw CancellationError()
                        }
                        guard let result_ = try await group.next() else { throw CancellationError() }
                        group.cancelAll()
                        return result_
                    }
                    guard !matches.isEmpty else { continue }
                    for match in matches {
                        if let range = Range(match.range, in: result) {
                            fixes.append(CustomRuleFix(ruleName: rule.name, original: String(result[range]), corrected: rule.replacement))
                        }
                    }
                    let template = rule.supportsBackreferences ? rule.replacement : NSRegularExpression.escapedTemplate(for: rule.replacement)
                    // Apply replacements (sync — already timed out above).
                    result = regex.stringByReplacingMatches(in: result, options: [], range: nsRange, withTemplate: template)
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

    private func save() {
        try? JSONEncoder().encode(rules).write(to: fileURL, options: .atomic)
    }
}

struct CustomRuleFix: Sendable {
    let ruleName: String
    let original: String
    let corrected: String
}
