import Foundation

final class StubLLMService: LLMService, @unchecked Sendable {
    static let shared = StubLLMService()

    func correct(text: String, promptType: PromptType) async throws -> CorrectionResult {
        try await Task.sleep(for: .milliseconds(500))

        let fakeCorrection: String
        switch promptType {
        case .grammar:
            fakeCorrection = "\(text)\n\n[CORRETTO-STUB: Errori grammaticali corretti]"
        case .fluency:
            fakeCorrection = "[FLUENCY-STUB] \(text) (fluidita migliorata)"
        case .explain:
            fakeCorrection = "Spiegazione stub: il testo originale contiene potenziali errori grammaticali da analizzare."
        case .custom:
            fakeCorrection = "\(text)\n\n[CUSTOM-STUB: Elaborato con regole personalizzate]"
        }

        return CorrectionResult(
            original: text,
            corrected: fakeCorrection,
            modelID: "stub-v1",
            explanation: promptType == .explain
                ? "Spiegazione stub: il verbo era coniugato male. Prova a riformulare usando il tempo corretto."
                : nil,
            confidence: 0.95
        )
    }

    func explain(original: String, corrected: String) async throws -> String {
        try await Task.sleep(for: .milliseconds(300))
        return "Spiegazione stub: analisi grammaticale completata."
    }

    func streamCorrect(text: String, promptType: PromptType) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                let words = text.components(separatedBy: " ")
                for (i, word) in words.enumerated() {
                    continuation.yield(word + (i < words.count - 1 ? " " : ""))
                    try? await Task.sleep(for: .milliseconds(30))
                }
                continuation.finish()
            }
        }
    }
}
