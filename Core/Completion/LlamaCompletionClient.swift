import Foundation
import OSLog

/// Request body for llama-server's native `/completion` endpoint (prefix continuation).
/// NOTE: `/infill` is intentionally NOT used — verified 2026-05-29 that it yields nothing useful
/// with Parrot's instruct models (it needs a FIM-trained model). `/completion` works well.
struct LlamaCompletionRequest: Encodable, Equatable {
    let prompt: String
    let n_predict: Int
    let temperature: Double
    let cache_prompt: Bool
    let stream: Bool
    let stop: [String]

    /// ~1.4 tokens/word heuristic, plus headroom, so `maxWords` words can actually emerge.
    init(prompt: String, maxWords: Int, temperature: Double = Constants.completionTemperature) {
        self.prompt = prompt
        self.n_predict = max(4, Int(Double(maxWords) * 1.8) + 2)
        self.temperature = temperature
        self.cache_prompt = true
        self.stream = false
        self.stop = ["\n"]   // short completions never cross a line break
    }
}

private struct LlamaCompletionResponse: Decodable {
    let content: String
}

/// Talks to the warm `llama-server` subprocess over its native `/completion` endpoint.
/// Conforms to `CompletionProviding` so the engine can be unit-tested against a stub instead.
struct LlamaCompletionClient: CompletionProviding {
    /// Resolves the current server port (0 if not running).
    var portProvider: @Sendable () async -> Int = { await ServerManager.shared.currentPort }
    var session: URLSession = .shared

    /// Builds the prompt sent to `/completion`. End-of-text completion uses the prefix only;
    /// when a suffix exists it is appended as a soft hint (true infill needs a FIM model).
    static func buildPrompt(context: CompletionContext, userPrompt: String) -> String {
        let pre = String(context.preContext.suffix(Constants.completionMaxPrefixChars))
        // Prefix continuation: the model completes `pre`. userPrompt (personalization) is not
        // injected into the raw continuation prompt for base/instruct continuation — it would
        // contaminate the text. It is reserved for SP2 context shaping. Kept in the signature
        // for forward-compatibility.
        _ = userPrompt
        return pre
    }

    func complete(context: CompletionContext, maxWords: Int) async throws -> String {
        let port = await portProvider()
        guard port > 0, let url = URL(string: "http://127.0.0.1:\(port)/completion") else {
            throw CorrectionError.serverNotRunning
        }
        let prompt = Self.buildPrompt(context: context, userPrompt: "")
        let body = LlamaCompletionRequest(prompt: prompt, maxWords: maxWords)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw CorrectionError.serverTimeout
        }
        try Task.checkCancellation()
        let decoded = try JSONDecoder().decode(LlamaCompletionResponse.self, from: data)
        return decoded.content
    }
}
