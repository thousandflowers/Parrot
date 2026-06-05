import Foundation
import OSLog

/// Completion provider backed by any OpenAI-compatible API endpoint.
/// Configured via PreferencesStore: endpoint URL (e.g. "https://api.openai.com/v1") + API key.
/// Falls back to the local provider when the endpoint is empty.
actor OpenAICompletionClient: CompletionProviding {
    private let fallback = LlamaCompletionClient()

    func complete(context: CompletionContext, maxWords: Int) async throws -> String {
        let endpoint = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.completionOpenAIEndpoint) ?? ""
        let apiKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.completionOpenAIKey) ?? ""
        guard !endpoint.isEmpty, let url = URL(string: endpoint) else {
            return try await fallback.complete(context: context, maxWords: maxWords)
        }
        let pre = String(context.preContext.suffix(Constants.completionMaxPrefixChars))
        let nPredict = max(6, maxWords * 4)

        let effectivePrompt: String = {
            if let ov = context.userPromptOverride, !ov.isEmpty { return ov }
            if !context.personalizationInstructions.isEmpty { return context.personalizationInstructions }
            return ""
        }()
        return try await rawChatCompletion(url: url, apiKey: apiKey, prefix: pre, nPredict: nPredict, model: "", promptOverride: effectivePrompt, styleDescriptor: context.styleDescriptor)
    }

    private func rawChatCompletion(url: URL, apiKey: String, prefix: String, nPredict: Int, model: String, promptOverride: String, styleDescriptor: String) async throws -> String {
        let systemContent = LlamaCompletionClient.systemPrompt(userPrompt: promptOverride, styleDescriptor: styleDescriptor)
        if !apiKey.isEmpty {
            // Redact the key in logs
            Logger.infra.debug("OpenAI client: endpoint=\(url.absoluteString, privacy: .public) key=\(apiKey.prefix(4))…\(apiKey.suffix(4), privacy: .public)")
        }
        // The endpoint URL is expected to be the base (e.g. "https://api.openai.com/v1").
        // Append "/chat/completions" if it doesn't already end with it.
        let chatURL: URL = {
            let s = url.absoluteString.hasSuffix("/") ? url.absoluteString : url.absoluteString + "/"
            if s.hasSuffix("chat/completions") { return url }
            return URL(string: s + "chat/completions") ?? url
        }()
        let messages: [[String: String]] = [
            ["role": "system", "content": systemContent],
            ["role": "user", "content": prefix]
        ]
        let json: [String: Any] = [
            "model": model.isEmpty ? "gpt-4o-mini" : model,
            "messages": messages,
            "max_tokens": nPredict,
            "temperature": 0.3,
            "stream": false
        ]
        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        request.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: request)
        guard let http = resp as? HTTPURLResponse else { throw CorrectionError.serverTimeout }
        guard http.statusCode == 200 else {
            Logger.infra.error("OpenAI client: HTTP \(http.statusCode)")
            throw CorrectionError.serverTimeout
        }
        // Try standard OpenAI response format first, then fall back to llama-server style.
        struct OAIChoice: Decodable { struct Message: Decodable { let content: String? }; let message: Message? }
        struct OAIResponse: Decodable { let choices: [OAIChoice]? }
        if let oai = try? JSONDecoder().decode(OAIResponse.self, from: data),
           let c = oai.choices?.first?.message?.content, !c.isEmpty {
            return c
        }
        // Fall back to raw /completion response format (llama-server)
        struct RawResponse: Decodable { let content: String }
        if let raw = try? JSONDecoder().decode(RawResponse.self, from: data) {
            return raw.content
        }
        return ""
    }
}
