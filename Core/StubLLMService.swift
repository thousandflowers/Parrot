import Foundation

final class StubLLMService: LLMService, Sendable {
    static let shared = StubLLMService()

    func correct(text: String, promptType: PromptType, language: String) async throws -> CorrectionResult {
        try await Task.sleep(for: .milliseconds(500))

        let fakeCorrection: String
        switch promptType {
        case .grammar:
            fakeCorrection = applyGrammarCorrections(text)
        case .fluency:
            fakeCorrection = applyFluencyCorrections(text)
        case .coach:
            fakeCorrection = "[STUB · Writing coach]: \(applyGrammarCorrections(text))"
        case .explain:
            fakeCorrection = "Stub explanation: the original text contains potential grammar errors to analyze."
        case .custom:
            fakeCorrection = applyGrammarCorrections(text)
                + "\n\n---\n[STUB · Custom rules applied]"
        case .translation(let lang):
            fakeCorrection = "[STUB · Translation to \(lang)]: \(text)"
        case .deSlop:
            fakeCorrection = applyGrammarCorrections(text) + "\n\n---\n[STUB · De-slopped]"
        case .grammarAndFluency:
            fakeCorrection = applyFluencyCorrections(applyGrammarCorrections(text))
        case .aiPrompt:
            fakeCorrection = "[STUB · AI Prompt optimized]: \(applyGrammarCorrections(text))"
        case .expand:
            fakeCorrection = "[STUB · Expanded]: Gentile Professore,\n\nLa contatto per richiedere informazioni sull'esame e la possibilità di un colloquio.\n\nCordiali saluti"
        }

        return CorrectionResult(
            original: text,
            corrected: fakeCorrection,
            modelID: "stub-v1",
            explanation: {
                if case .explain = promptType {
                    return "Stub explanation: the verb was conjugated incorrectly. Try rephrasing using the correct tense."
                }
                return nil
            }(),
            confidence: 0.95,
            promptType: promptType.label
        )
    }

    func correctFluency(text: String) async throws -> CorrectionResult {
        try await Task.sleep(for: .milliseconds(500))
        return CorrectionResult(
            original: text,
            corrected: applyFluencyCorrections(text),
            modelID: "stub-v1",
            confidence: 0.95,
            promptType: "fluency"
        )
    }

    func explain(original: String, corrected: String) async throws -> String {
        try await Task.sleep(for: .milliseconds(300))
        return "Stub explanation: grammar analysis complete."
    }

    func streamCorrect(text: String, promptType: PromptType) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let corrected = switch promptType {
            case .grammar, .custom: applyGrammarCorrections(text)
            case .fluency, .grammarAndFluency: applyFluencyCorrections(text)
            case .coach: "[STUB · Coach]: \(applyGrammarCorrections(text))"
            case .explain: "Stub explanation..."
            case .translation(let lang): "[STUB · Translation to \(lang)]: \(text)"
            case .deSlop: "[STUB · De-slopped]: \(applyGrammarCorrections(text))"
            case .aiPrompt: "[STUB · AI Prompt]: \(applyGrammarCorrections(text))"
            case .expand: "[STUB · Expanded]: Gentile Professore,\n\nLa contatto per richiedere informazioni sull'esame e la possibilità di un colloquio.\n\nCordiali saluti"
            }
            let words = corrected.components(separatedBy: " ")
            let task = Task {
                var accumulated = ""
                for (i, word) in words.enumerated() {
                    guard !Task.isCancelled else { return }
                    accumulated += word + (i < words.count - 1 ? " " : "")
                    continuation.yield(accumulated)
                    try? await Task.sleep(for: .milliseconds(30))
                }
                guard !Task.isCancelled else { return }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Simulated corrections

    private func applyGrammarCorrections(_ text: String) -> String {
        var result = text
        // Capitalize first letter of each sentence
        let sentences = text.components(separatedBy: ". ")
        if sentences.count > 1 {
            result = sentences.map { s in
                guard let first = s.first else { return s }
                return String(first).uppercased() + s.dropFirst()
            }.joined(separator: ". ")
        }
        // Replace double spaces
        result = result.replacingOccurrences(of: "  ", with: " ")
        // Fix common English mistakes
        result = result.replacingOccurrences(of: " i ", with: " I ")
        result = result.replacingOccurrences(of: "dont", with: "don't")
        result = result.replacingOccurrences(of: "isnt", with: "isn't")
        result = result.replacingOccurrences(of: "arent", with: "aren't")
        result = result.replacingOccurrences(of: "cant", with: "can't")
        result = result.replacingOccurrences(of: "wont", with: "won't")
        result = result.replacingOccurrences(of: "couldnt", with: "couldn't")
        result = result.replacingOccurrences(of: "wouldnt", with: "wouldn't")
        // Fix common Italian mistakes
        result = result.replacingOccurrences(of: " e' ", with: " è ")
        result = result.replacingOccurrences(of: " un po' ", with: " un po' ")
        result = result.replacingOccurrences(of: "perche ", with: "perché ")
        result = result.replacingOccurrences(of: "Perche ", with: "Perché ")
        result = result.replacingOccurrences(of: "poiche ", with: "poiché ")
        // Fix trailing punctuation
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    private func applyFluencyCorrections(_ text: String) -> String {
        var result = applyGrammarCorrections(text)
        // Simulate fluency improvements: add transitions, vary sentence structure
        let sentences = result.components(separatedBy: ". ")
        if sentences.count >= 2 {
            let improved = sentences.enumerated().map { i, s in
                if i == 0 { return s }
                // Simulate improving flow with a connecting word
                if !s.lowercased().hasPrefix("e ") && !s.lowercased().hasPrefix("ma ")
                    && !s.lowercased().hasPrefix("quindi ") && !s.lowercased().hasPrefix("inoltre ") {
                    return "Inoltre, \(s.prefix(1).lowercased() + s.dropFirst())"
                }
                return s
            }
            result = improved.joined(separator: ". ")
        }
        return result
    }
}
