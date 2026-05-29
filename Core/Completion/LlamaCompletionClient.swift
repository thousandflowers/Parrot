import Foundation
import OSLog

/// Talks to a warm `llama-server` over the OpenAI-compatible `/v1/chat/completions` endpoint
/// using a tight "continue the text" system prompt.
///
/// Why chat, not `/completion`/`/infill`: Parrot's models are instruct-tuned. Verified 2026-05-29
/// that raw `/completion` on an instruct model produces off-context/empty output; a chat
/// continuation prompt produces relevant short continuations. `/infill` needs a FIM model.
///
/// Model/server selection (user-configurable):
/// - `completionModelID` empty or == the main model → reuse the main correction server.
/// - otherwise → a dedicated `ServerManager.completion` instance runs the chosen model so the
///   user can trade a separate fast/base completion model against the heavier correction model.
struct LlamaCompletionClient: CompletionProviding {
    var session: URLSession = .shared

    static func systemPrompt(userPrompt: String) -> String {
        var s = "You are an autocomplete engine. Continue the user's text naturally in the SAME language. "
            + "Output ONLY the continuation that directly follows the text — do NOT repeat or restate the "
            + "user's text, no quotes, no explanation. Keep it short: a few words."
        let trimmed = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { s += "\nWriting style to match: \(trimmed)" }
        return s
    }

    /// Resolves which server port + model name to use for completion.
    private func resolveTarget() async -> (port: Int, model: String)? {
        let mainID = (UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.selectedModelID) ?? "")
            .replacingOccurrences(of: ".gguf", with: "")
        let compID = (UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.completionModelID) ?? "")
            .trimmingCharacters(in: .whitespaces)

        func mainTarget() async -> (Int, String)? {
            let port = await ServerManager.shared.currentPort
            return port > 0 ? (port, mainID.isEmpty ? "local" : mainID) : nil
        }

        if compID.isEmpty || compID.caseInsensitiveCompare(mainID) == .orderedSame {
            return await mainTarget()
        }
        // Dedicated completion model on its own server.
        guard let model = await ModelManager.shared.localModels()
                .first(where: { $0.id.caseInsensitiveCompare(compID) == .orderedSame }) else {
            Logger.infra.debug("completion: model '\(compID, privacy: .public)' not found locally — falling back to main")
            return await mainTarget()
        }
        do {
            let port = try await ServerManager.completion.ensureRunning(modelPath: model.path)
            return (port, model.id)
        } catch {
            Logger.infra.debug("completion: dedicated server failed (\(error.localizedDescription, privacy: .public)) — falling back to main")
            return await mainTarget()
        }
    }

    func complete(context: CompletionContext, maxWords: Int) async throws -> String {
        guard let (port, model) = await resolveTarget(),
              let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions") else {
            throw CorrectionError.serverNotRunning
        }
        let pre = String(context.preContext.suffix(Constants.completionMaxPrefixChars))
        let userPrompt = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.completionUserPrompt) ?? ""
        let messages = [
            ChatMessage(role: "system", content: Self.systemPrompt(userPrompt: userPrompt)),
            ChatMessage(role: "user", content: pre)
        ]
        let body = ChatRequest(
            model: model, messages: messages,
            temperature: Constants.completionTemperature,
            // Generate enough tokens for WHOLE words (avoid mid-word cut-off like "Sono fel"),
            // then trim to `maxWords` in the postprocessor. Decoupled so "short" never means "cut".
            max_tokens: max(12, maxWords * 5),
            stream: false,
            // Anti-repetition is critical for small models: without it they loop
            // ("Non posso amare. Non posso amare."). Verified to also improve relevance.
            sampling: SamplingParams(topP: 0.9, topK: 40, minP: 0.05, repeatPenalty: 1.3,
                                     seed: nil, frequencyPenalty: 0.7, presencePenalty: 0.4)
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
