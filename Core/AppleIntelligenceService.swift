import Foundation
import FoundationModels

@available(macOS 26.0, *)
actor AppleIntelligenceService: @preconcurrency LLMService {
    static let shared = AppleIntelligenceService()

    private let modelID = "apple-intelligence"

    private func makeSession() -> LanguageModelSession? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        return LanguageModelSession(model: .default)
    }

    nonisolated var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    nonisolated var availabilityDescription: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "Apple Intelligence ready"
        case .unavailable(.deviceNotEligible):
            return "Device not eligible for Apple Intelligence"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence not enabled in System Settings"
        case .unavailable(.modelNotReady):
            return "Apple Intelligence model is downloading"
        case .unavailable(let reason):
            return "Apple Intelligence unavailable: \(reason)"
        @unknown default:
            return "Apple Intelligence status unknown"
        }
    }

    func handleOpenAIHTTPStatus(_ statusCode: Int, data: Data) throws {
        switch statusCode {
        case 200: return
        case 500, 502: throw CorrectionError.serverTimeout
        case 503: throw CorrectionError.serverNotRunning
        default: throw CorrectionError.outputParsingFailed(raw: "HTTP \(statusCode)")
        }
    }

    func correct(text: String, promptType: PromptType, language: String) async throws -> CorrectionResult {
        let lang = language.isEmpty
            ? LanguageDetector.detect(text: text, fallbackLanguage: resolvedLanguage)
            : language
        let engine = PromptEngine(language: lang, style: await resolveStyle())
        let prompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)

        let corrected = try await generate(prompt)
        let validated = validateCorrection(original: text, corrected: corrected, isFluency: promptType.isFluency)

        return CorrectionResult(
            original: text, corrected: validated,
            modelID: modelID, confidence: Constants.defaultConfidence, promptType: promptType.label
        )
    }

    func correctFluency(text: String) async throws -> CorrectionResult {
        try await correct(text: text, promptType: .fluency, language: "")
    }

    func explain(original: String, corrected: String) async throws -> String {
        let lang = LanguageDetector.detect(text: corrected, fallbackLanguage: resolvedLanguage)
        let engine = PromptEngine(language: lang)
        let prompt = engine.buildExplainPrompt(original: original, corrected: corrected, customInstruction: nil)
        return try await generate(prompt)
    }

    func streamCorrect(text: String, promptType: PromptType) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let lang = LanguageDetector.detect(text: text, fallbackLanguage: resolvedLanguage)
                    let engine = PromptEngine(language: lang, style: await resolveStyle())
                    let prompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)

                    guard let session = makeSession() else {
                        throw CorrectionError.modelNotLoaded
                    }

                    let stream = session.streamResponse(to: prompt)
                    for try await snapshot in stream {
                        guard !Task.isCancelled else { return }
                        let text = String(snapshot.content)
                        // The continuation is bridged through a MainActor hop to
                        // ensure UI-visible state updates happen on the main thread.
                        // Explicitly type-erase to avoid the "non-Sendable in @Sendable"
                        // warning that plain continuation.yield triggers.
                        let yield: @Sendable () -> Void = { continuation.yield(text) }
                        await MainActor.run { yield() }
                    }

                    continuation.finish()
                } catch {
                    guard !Task.isCancelled else { return }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func generate(_ prompt: String) async throws -> String {
        guard let session = makeSession() else {
            throw CorrectionError.modelNotLoaded
        }
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
