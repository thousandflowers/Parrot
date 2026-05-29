import Foundation
import OSLog

/// Talks to a warm `llama-server` for inline completion.
///
/// Two paths, picked by which model serves the request:
/// - **Dedicated completion model** (`completionModelID` set, its own server): RAW `/completion`
///   (prefix continuation). Base models (e.g. gemma-3-4b-pt, as Cotypist uses) continue text far
///   better this way than via chat. Verified 2026-05-29: relevant, on-topic continuations.
/// - **Same as the main model** (instruct): `/v1/chat/completions` with a "continue the text"
///   system prompt, because raw `/completion` on an instruct model produces garbage.
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

    private struct Target { let port: Int; let model: String; let useRawCompletion: Bool }
    private struct RawCompletionResponse: Decodable { let content: String }

    /// Resolves which server + model to use, and whether to use the raw `/completion` endpoint.
    private func resolveTarget() async -> Target? {
        let mainID = (UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.selectedModelID) ?? "")
            .replacingOccurrences(of: ".gguf", with: "")
        let compID = (UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.completionModelID) ?? "")
            .trimmingCharacters(in: .whitespaces)

        func mainTarget() async -> Target? {
            let port = await ServerManager.shared.currentPort
            return port > 0 ? Target(port: port, model: mainID.isEmpty ? "local" : mainID, useRawCompletion: false) : nil
        }

        if compID.isEmpty || compID.caseInsensitiveCompare(mainID) == .orderedSame {
            return await mainTarget()
        }
        let local = await ModelManager.shared.localModels()
        guard let model = local.first(where: { $0.id.caseInsensitiveCompare(compID) == .orderedSame }) else {
            Logger.infra.debug("completion: model '\(compID, privacy: .public)' not local — falling back to main")
            return await mainTarget()
        }
        // RAM guard: running a dedicated completion model AND a different correction model means two
        // models + two servers resident at once. On low-RAM machines (e.g. 8GB) that swaps and can
        // freeze the system. If the combined model size exceeds a safe fraction of physical RAM,
        // fall back to a single shared model. Auto-adapts: 8GB → single, 16GB → dedicated allowed.
        let ramBytes = Double(ProcessInfo.processInfo.physicalMemory)
        let mainSize = Double(local.first(where: { $0.id.caseInsensitiveCompare(mainID) == .orderedSame })?.size ?? 0)
        let combined = mainSize + Double(model.size)
        if combined > ramBytes * 0.30 {
            Logger.infra.info("completion: combined models too large for RAM — using single shared model")
            return await mainTarget()
        }
        do {
            let port = try await ServerManager.completion.ensureRunning(modelPath: model.path)
            return Target(port: port, model: model.id, useRawCompletion: true)
        } catch {
            Logger.infra.debug("completion: dedicated server failed (\(error.localizedDescription, privacy: .public)) — main fallback")
            return await mainTarget()
        }
    }

    func complete(context: CompletionContext, maxWords: Int) async throws -> String {
        guard let target = await resolveTarget() else { throw CorrectionError.serverNotRunning }
        let pre = String(context.preContext.suffix(Constants.completionMaxPrefixChars))
        // Generate enough tokens for WHOLE words (avoid mid-word cut-off), trim to maxWords in post.
        let nPredict = max(12, maxWords * 5)

        if target.useRawCompletion {
            return try await rawCompletion(prefix: pre, port: target.port, nPredict: nPredict)
        } else {
            return try await chatCompletion(prefix: pre, model: target.model, port: target.port, nPredict: nPredict)
        }
    }

    // MARK: - Raw /completion (base completion model)
    private func rawCompletion(prefix: String, port: Int, nPredict: Int) async throws -> String {
        guard let url = URL(string: "http://127.0.0.1:\(port)/completion") else { throw CorrectionError.serverNotRunning }
        let payload: [String: Any] = [
            "prompt": prefix,
            "n_predict": nPredict,
            "temperature": Constants.completionTemperature,
            "top_p": 0.9, "repeat_penalty": 1.3, "frequency_penalty": 0.7, "presence_penalty": 0.4,
            "cache_prompt": true,         // reuse KV across keystrokes → much lower latency
            "stop": ["\n"]
        ]
        let data = try await post(url: url, json: payload)
        return (try? JSONDecoder().decode(RawCompletionResponse.self, from: data).content) ?? ""
    }

    // MARK: - Chat completion (instruct main model)
    private func chatCompletion(prefix: String, model: String, port: Int, nPredict: Int) async throws -> String {
        guard let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions") else { throw CorrectionError.serverNotRunning }
        let userPrompt = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.completionUserPrompt) ?? ""
        let body = ChatRequest(
            model: model,
            messages: [ChatMessage(role: "system", content: Self.systemPrompt(userPrompt: userPrompt)),
                       ChatMessage(role: "user", content: prefix)],
            temperature: Constants.completionTemperature, max_tokens: nPredict, stream: false,
            sampling: SamplingParams(topP: 0.9, topK: 40, minP: 0.05, repeatPenalty: 1.3,
                                     seed: nil, frequencyPenalty: 0.7, presencePenalty: 0.4)
        )
        let data = try await post(url: url, body: try JSONEncoder().encode(body))
        return (try? JSONDecoder().decode(ChatResponse.self, from: data))?.choices.first?.message.content ?? ""
    }

    // MARK: - HTTP
    private func post(url: URL, json: [String: Any]) async throws -> Data {
        try await post(url: url, body: try JSONSerialization.data(withJSONObject: json))
    }
    private func post(url: URL, body: Data) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 10
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw CorrectionError.serverTimeout }
        try Task.checkCancellation()
        return data
    }
}
