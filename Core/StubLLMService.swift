import Foundation

final class StubLLMService: LLMService, Sendable {
    static let shared = StubLLMService()

    func correct(text: String, promptType: PromptType) async throws -> CorrectionResult {
        try await Task.sleep(for: .milliseconds(500))

        let fakeCorrection: String
        switch promptType {
        case .grammar:
            fakeCorrection = "\(text)\n\n[CORRETTO-STUB: Errori grammaticali corretti]"
        case .fluency:
            fakeCorrection = "[FLUENCY-STUB] \(text) (fluidità migliorata)"
        case .explain:
            fakeCorrection = "Spiegazione stub: il testo originale contiene potenziali errori grammaticali da analizzare."
        case .custom:
            fakeCorrection = "\(text)\n\n[CUSTOM-STUB: Elaborato con regole personalizzate]"
        case .translation(let target):
            fakeCorrection = "[TRADUZIONE: \(text)] (tradotto in \(target) -- stub)"
        case .coach:
            fakeCorrection = "[COACH-STUB] Analisi del testo:\n\n1. **Grammatica**: Nessun errore rilevato.\n2. **Stile**: Considera di variare la lunghezza delle frasi.\n3. **Tono**: Appropriato per il contesto.\n4. **Chiarezza**: Testo chiaro e ben strutturato."
        }

        return CorrectionResult(
            original: text,
            corrected: fakeCorrection,
            modelID: "stub-v1",
            explanation: {
                if case .explain = promptType {
                    return "Spiegazione stub: il verbo era coniugato male. Prova a riformulare usando il tempo corretto."
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
            corrected: "[FLUENCY-STUB] \(text) (fluidità migliorata)",
            modelID: "stub-v1",
            confidence: 0.95,
            promptType: "fluency"
        )
    }

    func explain(original: String, corrected: String) async throws -> String {
        try await Task.sleep(for: .milliseconds(300))
        return "Spiegazione stub: analisi grammaticale completata."
    }

    func streamCorrect(text: String, promptType: PromptType) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let words = text.components(separatedBy: " ")
                for (i, word) in words.enumerated() {
                    guard !Task.isCancelled else { return }
                    continuation.yield(word + (i < words.count - 1 ? " " : ""))
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
}
