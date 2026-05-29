import Foundation
import OSLog

/// Talks to the warm `llama-server` over the OpenAI-compatible `/v1/chat/completions` endpoint
/// using a tight "continue the text" system prompt.
///
/// Why chat, not `/completion` or `/infill`: Parrot's models are instruct-tuned. Verified
/// 2026-05-29 that raw `/completion` on an instruct model produces off-context / empty output,
/// while a chat continuation prompt produces relevant short continuations (even for code).
/// `/infill` needs a FIM model (none here).
struct LlamaCompletionClient: CompletionProviding {
    var portProvider: @Sendable () async -> Int = { await ServerManager.shared.currentPort }
    var modelProvider: @Sendable () -> String = {
        let id = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.selectedModelID)
        return id?.replacingOccurrences(of: ".gguf", with: "") ?? "local"
    }
    var userPromptProvider: @Sendable () -> String = {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.completionUserPrompt) ?? ""
    }
    var session: URLSession = .shared

    static func systemPrompt(userPrompt: String) -> String {
        var s = "You are an autocomplete engine. Continue the user's text naturally in the SAME language. "
            + "Output ONLY the continuation that directly follows the text — do NOT repeat or restate the "
            + "user's text, no quotes, no explanation. Keep it short: a few words."
        let trimmed = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { s += "\nWriting style to match: \(trimmed)" }
        return s
    }

    func complete(context: CompletionContext, maxWords: Int) async throws -> String {
        let port = await portProvider()
        guard port > 0, let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions") else {
            throw CorrectionError.serverNotRunning
        }
        let pre = String(context.preContext.suffix(Constants.completionMaxPrefixChars))
        let messages = [
            ChatMessage(role: "system", content: Self.systemPrompt(userPrompt: userPromptProvider())),
            ChatMessage(role: "user", content: pre)
        ]
        let body = ChatRequest(
            model: modelProvider(), messages: messages,
            temperature: Constants.completionTemperature,
            max_tokens: max(8, Int(Double(maxWords) * 1.8) + 4),
            stream: false,
            sampling: SamplingParams(topP: 0.9, topK: 40, minP: 0.05, repeatPenalty: 1.1, seed: nil)
        )

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
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }
}
