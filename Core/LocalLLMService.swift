import Foundation

actor LocalLLMService: @preconcurrency LLMService {
    static let shared = LocalLLMService()

    nonisolated private var language: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.language) ?? "it"
    }

    func correct(text: String, promptType: PromptType) async throws -> CorrectionResult {
        let engine = PromptEngine(language: language)
        let fullPrompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)

        let port = await ServerManager.shared.currentPort
        guard port > 0 else { throw CorrectionError.serverNotRunning }

        let body: [String: Any] = [
            "model": "local-model",
            "messages": [
                ["role": "system", "content": "You are a helpful writing assistant. Follow the user instructions exactly."],
                ["role": "user", "content": fullPrompt]
            ],
            "temperature": 0.1,
            "max_tokens": 1024,
            "stream": false
        ]

        let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!
        let request = try buildLLMRequest(url: url, apiKey: nil, body: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CorrectionError.serverNotRunning
        }
        switch httpResponse.statusCode {
        case 200: break
        case 503: throw CorrectionError.serverNotRunning
        case 500: throw CorrectionError.serverTimeout
        default: throw CorrectionError.outputParsingFailed(raw: "HTTP \(httpResponse.statusCode)")
        }

        let corrected = try parseResponse(data: data)
        return CorrectionResult(
            original: text,
            corrected: corrected.isEmpty ? text : corrected,
            modelID: "local-qwen",
            confidence: 0.9,
            promptType: promptType.label
        )
    }

    func correctFluency(text: String) async throws -> CorrectionResult {
        let engine = PromptEngine(language: language)
        let fluencyPrompt = engine.buildFluencyPrompt(for: text, customInstruction: nil)

        let port = await ServerManager.shared.currentPort
        guard port > 0 else { throw CorrectionError.serverNotRunning }

        let body: [String: Any] = [
            "model": "local-model",
            "messages": [
                ["role": "system", "content": "You are a helpful writing assistant. Follow the user instructions exactly."],
                ["role": "user", "content": fluencyPrompt]
            ],
            "temperature": 0.3,
            "max_tokens": 1024,
            "stream": false
        ]

        let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!
        let request = try buildLLMRequest(url: url, apiKey: nil, body: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CorrectionError.serverNotRunning
        }
        switch httpResponse.statusCode {
        case 200: break
        case 503: throw CorrectionError.serverNotRunning
        case 500: throw CorrectionError.serverTimeout
        default: throw CorrectionError.outputParsingFailed(raw: "HTTP \(httpResponse.statusCode)")
        }

        let corrected = try parseResponse(data: data)
        return CorrectionResult(
            original: text,
            corrected: corrected.isEmpty ? text : corrected,
            modelID: "local-qwen",
            confidence: 0.9,
            promptType: "fluency"
        )
    }

    func explain(original: String, corrected: String) async throws -> String {
        let engine = PromptEngine(language: language)
        let explainPrompt = engine.buildExplainPrompt(original: original, corrected: corrected, customInstruction: nil)

        let port = await ServerManager.shared.currentPort
        guard port > 0 else { throw CorrectionError.serverNotRunning }

        let body: [String: Any] = [
            "model": "local-model",
            "messages": [["role": "user", "content": explainPrompt]],
            "temperature": 0.3,
            "max_tokens": 512,
            "stream": false
        ]
        let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!
        let request = try buildLLMRequest(url: url, apiKey: nil, body: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CorrectionError.serverNotRunning
        }
        return try parseResponse(data: data)
    }

    func streamCorrect(text: String, promptType: PromptType) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                do {
                    let result = try await correct(text: text, promptType: promptType)
                    continuation.yield(result.correctedText)
                } catch {
                    continuation.yield("[Error: \(error.localizedDescription)]")
                }
                continuation.finish()
            }
        }
    }
}
