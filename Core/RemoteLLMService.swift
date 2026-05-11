import Foundation
import os

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
            os_log(.debug, "Keychain load openai: %{public}@", error.localizedDescription)
            throw CorrectionError.invalidAPIKey
        } catch {
            os_log(.debug, "Keychain unexpected: %{public}@", error.localizedDescription)
            throw CorrectionError.invalidAPIKey
        }
    }

    func correct(text: String, promptType: PromptType) async throws -> CorrectionResult {
        let apiKey = try loadAPIKey()
        guard !apiKey.isEmpty else { throw CorrectionError.invalidAPIKey }
        return try await performCorrection(text: text, promptType: promptType,
            model: openAIModel, url: try chatURL(), apiKey: apiKey)
    }

    func correctFluency(text: String) async throws -> CorrectionResult {
        let apiKey = try loadAPIKey()
        guard !apiKey.isEmpty else { throw CorrectionError.invalidAPIKey }
        return try await performCorrection(text: text, promptType: .fluency,
            model: openAIModel, url: try chatURL(), apiKey: apiKey)
    }

    func explain(original: String, corrected: String) async throws -> String {
        let engine = PromptEngine(language: resolvedLanguage)
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
                    let engine = PromptEngine(language: resolvedLanguage)
                    let prompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)
                    let apiKey = try loadAPIKey()
                    guard !apiKey.isEmpty else {
                        throw CorrectionError.invalidAPIKey
                    }
                    let model = openAIModel

                    let stream = performOpenAIStreamRequest(
                        body: chatBody(model: model, prompt: prompt, temperature: 0.1, stream: true),
                        url: try chatURL(),
                        apiKey: apiKey
                    )
                    var fullText = ""
                    for try await chunk in stream {
                        fullText += chunk
                        continuation.yield(fullText)
                    }
                    if fullText.isEmpty {
                        continuation.finish(throwing: CorrectionError.outputParsingFailed(raw: "empty"))
                    } else {
                        continuation.finish()
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
