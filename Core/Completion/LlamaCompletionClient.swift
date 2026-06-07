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

    static func systemPrompt(userPrompt: String, styleDescriptor: String = "") -> String {
        var s = "Continue the user's text naturally in the SAME language. Output ONLY the few words that directly follow — no restating, no explanation, no quotes."
        let trimmed = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { s += "\nWriting style to match: \(trimmed)" }
        if !styleDescriptor.isEmpty { s += "\n" + styleDescriptor }
        return s
    }

    private struct Target { let port: Int; let model: String; let useRawCompletion: Bool }
    private struct RawCompletionResponse: Decodable { let content: String }

    /// Whether the chosen completion model should use the raw `/completion` endpoint instead of the
    /// instruct `/v1/chat/completions` one. Semantics: a model the user picked in the *completion*
    /// slot is a base/continuation model (e.g. gemma-3-4b-pt) — it continues raw text and ignores
    /// chat instructions, so it MUST go through `/completion`. An empty slot means no dedicated
    /// completion model → fall back to the correction (instruct) model via chat.
    static func usesRawCompletion(completionModelID: String) -> Bool {
        !completionModelID.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Resolves which server + model to use, and whether to use the raw `/completion` endpoint.
    private func resolveTarget(context: CompletionContext) async -> Target? {
        let mainID = context.selectedModelID
            .replacingOccurrences(of: ".gguf", with: "")
        let compID = context.completionModelID
            .trimmingCharacters(in: .whitespaces)
        let useRaw = Self.usesRawCompletion(completionModelID: context.completionModelID)

        func mainTarget(useRawCompletion: Bool) async -> Target? {
            // Reuse a server that's already up (Parrot warms one; an external llama-server may exist).
            let running = await ServerManager.shared.currentPort
            if running > 0 {
                return Target(port: running, model: mainID.isEmpty ? "local" : mainID, useRawCompletion: useRawCompletion)
            }
            // Nothing running. Wren (completion-only) never warms a correction server, so start one now
            // with the selected model — or any local model — otherwise completion silently never works.
            let local = await ModelManager.shared.localModels()
            let modelPath = local.first(where: { $0.id.caseInsensitiveCompare(mainID) == .orderedSame })?.path
                ?? local.first?.path
            guard let modelPath else {
                Logger.infra.error("completion: no local model available — inline completion cannot run")
                return nil
            }
            do {
                let port = try await ServerManager.shared.ensureRunning(modelPath: modelPath)
                return port > 0 ? Target(port: port, model: mainID.isEmpty ? "local" : mainID, useRawCompletion: useRawCompletion) : nil
            } catch {
                Logger.infra.error("completion: main server start failed — \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }

        // No dedicated completion model → use the correction model through the instruct chat endpoint.
        guard useRaw else { return await mainTarget(useRawCompletion: false) }
        // Same model in both slots: reuse the single running server (no second spawn), but it IS a
        // chosen completion (base) model → drive it via raw `/completion`, not chat.
        if compID.caseInsensitiveCompare(mainID) == .orderedSame {
            return await mainTarget(useRawCompletion: true)
        }
        let local = await ModelManager.shared.localModels()
        guard let model = local.first(where: { $0.id.caseInsensitiveCompare(compID) == .orderedSame }) else {
            Logger.infra.debug("completion: model '\(compID, privacy: .public)' not local — falling back to main")
            return await mainTarget(useRawCompletion: useRaw)
        }
        // RAM guard: running a dedicated completion model AND a different correction model means two
        // models + two servers resident at once. On low-RAM machines (e.g. 8GB) that swaps and can
        // freeze the system. If the combined model size exceeds a safe fraction of physical RAM,
        // fall back to a single shared model. Auto-adapts: 8GB → single, 16GB → dedicated allowed.
        let ramBytes = Double(ProcessInfo.processInfo.physicalMemory)
        // On Wren the correction model is never resident (completion-only), so don't count its size
        // toward the combined-RAM budget — that over-counted and needlessly forced the shared-model
        // fallback. Only count it when this build actually runs correction (Parrot).
        let mainSize = AppMode.current.showsCorrection
            ? Double(local.first(where: { $0.id.caseInsensitiveCompare(mainID) == .orderedSame })?.size ?? 0)
            : 0
        let combined = mainSize + Double(model.size)
        if combined > ramBytes * 0.30 {
            Logger.infra.info("completion: combined models too large for RAM — using single shared model")
            return await mainTarget(useRawCompletion: useRaw)
        }
        do {
            let port = try await ServerManager.completion.ensureRunning(modelPath: model.path)
            return Target(port: port, model: model.id, useRawCompletion: true)
        } catch {
            Logger.infra.debug("completion: dedicated server failed (\(error.localizedDescription, privacy: .public)) — main fallback")
            return await mainTarget(useRawCompletion: useRaw)
        }
    }

    func complete(context: CompletionContext, maxWords: Int, allowCode: Bool) async throws -> String {
        guard let target = await resolveTarget(context: context) else { throw CorrectionError.serverNotRunning }
        let pre = String(context.preContext.suffix(Constants.completionMaxPrefixChars))
        let postText = String(context.postContext.prefix(Constants.completionMaxPrefixChars))
        // Generate enough tokens for WHOLE words (avoid mid-word cut-off), trim to maxWords in post.
        let nPredict = max(6, maxWords * 4)

        let promptOverride = context.userPromptOverride

        if target.useRawCompletion {
            return try await rawCompletion(prefix: pre, port: target.port, nPredict: nPredict)
        } else {
            return try await chatCompletion(context: context, prefix: pre, postText: postText, model: target.model, port: target.port, nPredict: nPredict, promptOverride: promptOverride)
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
    private func chatCompletion(context: CompletionContext, prefix: String, postText: String, model: String, port: Int, nPredict: Int, promptOverride: String? = nil) async throws -> String {
        let strength = context.personalizationStrength
        guard let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions") else { throw CorrectionError.serverNotRunning }
        // Priority: per-app rule override → personalizationInstructions → completionUserPrompt.
        let effectivePrompt: String = {
            if let ov = promptOverride, !ov.isEmpty { return ov }
            if !context.personalizationInstructions.isEmpty { return context.personalizationInstructions }
            return UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.completionUserPrompt) ?? ""
        }()
        // Scale temperature by personalization strength (0.0 = no influence, coldest; 1.0 = default temp).
        let temp = 0.1 + (Constants.completionTemperature - 0.1) * strength
        // Manual payload so we can pass llama-server's `cache_prompt`: reuses the KV cache of the
        // constant system prompt across keystrokes, cutting the ~2.6s prompt-eval after the first call
        // (the dominant latency that made suggestions arrive too late and get superseded).
        var userContent = prefix
        if !postText.isEmpty {
            userContent += "\n\n[this text comes AFTER the cursor, do NOT generate it: \(postText)]"
        }
        let styleDescriptor = await CompletionLearningStore.shared.styleDescriptor()
        let payload: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": Self.systemPrompt(userPrompt: effectivePrompt, styleDescriptor: styleDescriptor)],
                         ["role": "user", "content": userContent]],
            "temperature": temp,
            "max_tokens": nPredict,
            "stream": false,
            "cache_prompt": true,
            "stop": ["\n", "User:", "Assistant:"],
            "top_p": 0.9, "top_k": 40, "min_p": 0.05,
            "repeat_penalty": 1.3, "frequency_penalty": 0.7, "presence_penalty": 0.4
        ]
        let data = try await post(url: url, json: payload)
        return (try? JSONDecoder().decode(ChatResponse.self, from: data))?.choices.first?.message.content ?? ""
    }

    // MARK: - HTTP
    private func post(url: URL, json: [String: Any]) async throws -> Data {
        try await post(url: url, body: try JSONSerialization.data(withJSONObject: json))
    }
    private func post(url: URL, body: Data, retries: Int = 1) async throws -> Data {
        var lastError: Error = CorrectionError.serverTimeout
        for attempt in 0...retries {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(1))
                try Task.checkCancellation()
            }
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = body
                request.timeoutInterval = 10
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw CorrectionError.serverTimeout }
                try Task.checkCancellation()
                return data
            } catch {
                if error is URLError {
                    lastError = error
                    continue
                }
                throw error
            }
        }
        throw lastError
    }
}
