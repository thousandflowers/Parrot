import Foundation

struct StoryAnalysisResult: Sendable {
    let overallScore: Double
    let categories: [CategoryScore]
    let summary: String

    struct CategoryScore: Sendable {
        let name: String
        let score: Double
        let feedback: String
        let icon: String
    }
}

actor StoryAnalyzer {
    static let shared = StoryAnalyzer()
    private init() {}

    func analyze(text: String) async throws -> StoryAnalysisResult {
        let prompt = """
        Analyze the following text as a professional literary editor. Provide a structured analysis:

        1. **Plot/Structure** (1-10): Coherence, pacing, narrative arc
        2. **Characters** (1-10): Depth, consistency, motivation
        3. **Style/Voice** (1-10): Originality, tone consistency, prose quality
        4. **Dialogue** (1-10): Naturalness, character differentiation
        5. **World-building** (1-10): Setting detail, internal consistency
        6. **Pacing** (1-10): Rhythm, tension, chapter flow

        For each category, give: score (1-10), 2-3 sentence feedback.
        Then give an overall score (average) and a 1-paragraph summary.

        Format:
        CATEGORY_NAME: score/10 - feedback
        ...
        OVERALL: score/10
        SUMMARY: paragraph

        Text: \(text.prefix(5000))
        """

        let service = LLMServiceFactory.make()
        let result = try await service.correct(text: prompt, promptType: .coach, language: "en")

        return parseAnalysis(result.correctedText)
    }

    private func parseAnalysis(_ text: String) -> StoryAnalysisResult {
        var categories: [StoryAnalysisResult.CategoryScore] = []
        var overallScore: Double = 0
        var summary = ""

        let lines = text.components(separatedBy: .newlines)
        let icons = ["📖", "👤", "✍️", "💬", "🌍", "⏱️"]
        var iconIdx = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("OVERALL:") {
                let parts = trimmed.replacingOccurrences(of: "OVERALL:", with: "").trimmingCharacters(in: .whitespaces)
                if let score = Double(parts.components(separatedBy: "/").first ?? "0") {
                    overallScore = score
                }
            } else if trimmed.hasPrefix("SUMMARY:") {
                summary = trimmed.replacingOccurrences(of: "SUMMARY:", with: "").trimmingCharacters(in: .whitespaces)
            } else if let range = trimmed.range(of: ":") {
                let name = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let rest = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                let scoreStr = rest.components(separatedBy: "/").first ?? "0"
                if let score = Double(scoreStr.trimmingCharacters(in: .whitespaces)) {
                    let feedback = rest.components(separatedBy: "-").dropFirst().joined(separator: "-").trimmingCharacters(in: .whitespaces)
                    let icon = iconIdx < icons.count ? icons[iconIdx] : "📝"
                    iconIdx += 1
                    categories.append(StoryAnalysisResult.CategoryScore(
                        name: name, score: score, feedback: feedback.isEmpty ? rest : feedback, icon: icon
                    ))
                }
            }
        }

        if categories.isEmpty {
            categories = [StoryAnalysisResult.CategoryScore(name: "Analysis", score: overallScore, feedback: text, icon: "📝")]
        }

        return StoryAnalysisResult(overallScore: overallScore, categories: categories, summary: summary)
    }
}
