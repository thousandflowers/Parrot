import Foundation
import OSLog

final class RemoteLLMService: LLMService, Sendable {
    static let shared = RemoteLLMService()

    nonisolated private var openAIBaseURL: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.openAIBaseURL) ?? "https://api.openai.com/v1"
    }
    nonisolated private var openAIModel: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.openAIModel) ?? "gpt-4o-mini"
    }

    private func chatURL() throws -> URL {
        let base = openAIBaseURL.hasSuffix("/") ? String(openAIBaseURL.dropLast()) : openAIBaseURL
        guard let url = URL(string: "\(base)/chat/completions") else {
            throw CorrectionError.networkUnavailable
        }
        return url
    }

    private func loadAPIKey() throws -> String {
        do {
            return try KeychainService.shared.load(for: "openai")
        } catch let error as KeychainError {
            Logger.core.debug("Keychain load openai: \(error.localizedDescription, privacy: .public)")
            throw CorrectionError.invalidAPIKey
        } catch {
            Logger.core.debug("Keychain unexpected: \(error.localizedDescription, privacy: .public)")
            throw CorrectionError.invalidAPIKey
        }
    }

    func correct(text: String, promptType: PromptType, language: String) async throws -> CorrectionResult {
        let apiKey = try loadAPIKey()
        guard !apiKey.isEmpty else { throw CorrectionError.invalidAPIKey }
        return try await performCorrection(text: text, promptType: promptType, language: language,
            model: openAIModel, url: try chatURL(), apiKey: apiKey)
    }

    func correctFluency(text: String) async throws -> CorrectionResult {
        let apiKey = try loadAPIKey()
        guard !apiKey.isEmpty else { throw CorrectionError.invalidAPIKey }
        return try await performCorrection(text: text, promptType: .fluency,
            model: openAIModel, url: try chatURL(), apiKey: apiKey)
    }

    func explain(original: String, corrected: String) async throws -> String {
        let lang = LanguageDetector.detect(text: original, fallbackLanguage: resolvedLanguage)
        let engine = PromptEngine(language: lang)
        let prompt = engine.buildExplainPrompt(original: original, corrected: corrected, customInstruction: nil)
        let apiKey = try loadAPIKey()
        guard !apiKey.isEmpty else {
            throw CorrectionError.invalidAPIKey
        }

        return try await performOpenAIRequest(
            body: chatBody(model: openAIModel, prompt: prompt, systemPrompt: nil, temperature: Constants.fluencyTemperature, maxTokens: Constants.explainMaxTokens),
            url: try chatURL(),
            apiKey: apiKey
        )
    }

    func streamCorrect(text: String, promptType: PromptType) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let apiKey = try self.loadAPIKey()
                    guard !apiKey.isEmpty else { throw CorrectionError.invalidAPIKey }
                    let url = try self.chatURL()
                    for try await accumulated in self.defaultStreamCorrect(text: text, promptType: promptType, model: self.openAIModel, url: url, apiKey: apiKey) {
                        continuation.yield(accumulated)
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
}
