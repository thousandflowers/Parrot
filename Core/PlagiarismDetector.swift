import Foundation

struct PlagiarismResult: Sendable {
    let overallScore: Double
    let findings: [Finding]

    struct Finding: Sendable {
        let source: Source
        let matchText: String
        let confidence: Double
        let url: String?

        enum Source: String, Sendable {
            case webSearch = "Web Search"
            case knowledgeBase = "Knowledge Base"
            case externalAPI = "External API"
            case llmAnalysis = "LLM Style Analysis"
        }
    }
}

actor PlagiarismDetector {
    static let shared = PlagiarismDetector()
    private init() {}

    func detect(text: String, methods: Set<PlagiarismMethod>) async -> PlagiarismResult {
        var findings: [PlagiarismResult.Finding] = []

        if methods.contains(.knowledgeBase) {
            findings.append(contentsOf: await checkKnowledgeBase(text: text))
        }

        if methods.contains(.llmAnalysis) {
            findings.append(contentsOf: await checkLLMStyle(text: text))
        }

        if methods.contains(.webSearch) {
            findings.append(contentsOf: await checkWebSearch(text: text))
        }

        let overallScore = findings.map { $0.confidence }.max() ?? 0
        return PlagiarismResult(overallScore: overallScore, findings: findings)
    }

    private func checkKnowledgeBase(text: String) async -> [PlagiarismResult.Finding] {
        let docs = await KnowledgeBase.shared.allDocuments.filter { $0.source == .file }
        var findings: [PlagiarismResult.Finding] = []

        for doc in docs {
            let similarity = jaccardSimilarity(text1: text, text2: doc.content)
            if similarity > 0.3 {
                findings.append(PlagiarismResult.Finding(
                    source: .knowledgeBase,
                    matchText: String(doc.content.prefix(200)),
                    confidence: similarity,
                    url: nil
                ))
            }
        }

        return findings
    }

    private func checkLLMStyle(text: String) async -> [PlagiarismResult.Finding] {
        let prompt = """
        Analyze this text for signs that it may have been copied or AI-generated.
        Look for: sudden style changes, inconsistent tone, overly generic phrasing,
        AI-typical patterns (repetitive structures, hedging, formulaic transitions).

        Text: \(text.prefix(2000))

        Respond with: SUSPECTED or CLEAN, followed by a brief reason.
        """

        do {
            let service = LLMServiceFactory.make()
            let result = try await service.correct(text: prompt, promptType: .grammar, language: "en")
            let isSuspected = result.correctedText.uppercased().contains("SUSPECTED")
            if isSuspected {
                return [PlagiarismResult.Finding(
                    source: .llmAnalysis,
                    matchText: String(text.prefix(200)),
                    confidence: 0.6,
                    url: nil
                )]
            }
        } catch {}

        return []
    }

    private func checkWebSearch(text: String) async -> [PlagiarismResult.Finding] {
        let keyPhrases = extractKeyPhrases(from: text)
        var findings: [PlagiarismResult.Finding] = []

        for phrase in keyPhrases.prefix(3) {
            let url = "https://www.google.com/search?q=\(phrase.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            findings.append(PlagiarismResult.Finding(
                source: .webSearch,
                matchText: phrase,
                confidence: 0.3,
                url: url
            ))
        }

        return findings
    }

    private func jaccardSimilarity(text1: String, text2: String) -> Double {
        let words1 = Set(text1.lowercased().split(separator: " ").filter { $0.count > 3 })
        let words2 = Set(text2.lowercased().split(separator: " ").filter { $0.count > 3 })
        let intersection = words1.intersection(words2)
        let union = words1.union(words2)
        guard !union.isEmpty else { return 0 }
        return Double(intersection.count) / Double(union.count)
    }

    private func extractKeyPhrases(from text: String) -> [String] {
        let sentences = text.components(separatedBy: .punctuationCharacters)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.split(separator: " ").count >= 4 }
        return Array(sentences.prefix(5))
    }
}

enum PlagiarismMethod: String, CaseIterable, Identifiable {
    case webSearch = "Web Search"
    case knowledgeBase = "Knowledge Base"
    case externalAPI = "External API"
    case llmAnalysis = "LLM Style Analysis"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .webSearch: "globe"
        case .knowledgeBase: "book.closed"
        case .externalAPI: "cloud"
        case .llmAnalysis: "brain"
        }
    }
}
