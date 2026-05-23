import Foundation
import OSLog

// MARK: - Utility condivisa (tutti i servizi LLM)

extension LLMService {

    func parseResponse(data: Data) throws -> String {
        do {
            let response = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard let content = response.choices.first?.message.content, !content.isEmpty else {
                throw CorrectionError.outputParsingFailed(raw: String(data: data, encoding: .utf8) ?? "nil")
            }
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch is CorrectionError {
            throw CorrectionError.outputParsingFailed(raw: String(data: data, encoding: .utf8) ?? "nil")
        } catch {
            throw CorrectionError.outputParsingFailed(raw: String(data: data, encoding: .utf8) ?? error.localizedDescription)
        }
    }

    func buildLLMRequest(url: URL, apiKey: String?, body: ChatRequest) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Constants.requestTimeout
        if let key = apiKey {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    func performOpenAIRequest(
        body: ChatRequest,
        url: URL,
        apiKey: String?,
        extraHeaders: [String: String] = [:]
    ) async throws -> String {
        try throwIfInvalidLLMURL(url)
        var request = try buildLLMRequest(url: url, apiKey: apiKey, body: body)
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        var lastError: Error?
        for attempt in 0..<Constants.requestMaxAttempts {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw CorrectionError.networkUnavailable
                }
                try handleOpenAIHTTPStatus(httpResponse.statusCode, data: data)
                let result = try parseResponse(data: data)
                guard !result.isEmpty else {
                    throw CorrectionError.outputParsingFailed(raw: "empty")
                }
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as CorrectionError {
                switch error {
                case .invalidAPIKey, .rateLimited, .outputParsingFailed, .modelNotLoaded:
                    throw error
                default:
                    lastError = error
                }
            } catch let error as URLError {
                lastError = mapURLError(error)
            } catch {
                lastError = error
            }
            guard attempt < Constants.requestMaxAttempts - 1 else { break }
            let delayMs = UInt64(min(2000, 250 * Int(pow(2.0, Double(attempt)))))
            try await Task.sleep(for: .milliseconds(delayMs))
        }
        throw lastError ?? CorrectionError.networkUnavailable
    }

    private func throwIfInvalidLLMURL(_ url: URL) throws {
        guard let scheme = url.scheme, ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            throw CorrectionError.networkUnavailable
        }
    }

    func mapURLError(_ error: URLError) -> CorrectionError {
        switch error.code {
        case .cannotConnectToHost, .networkConnectionLost: return .serverNotRunning
        case .timedOut:                                     return .serverTimeout
        case .notConnectedToInternet:                       return .networkUnavailable
        default:                                            return .networkUnavailable
        }
    }

    func handleOpenAIHTTPStatus(_ statusCode: Int, data: Data) throws {
        switch statusCode {
        case 200:        return
        case 401, 403:   throw CorrectionError.invalidAPIKey
        case 429:        throw CorrectionError.rateLimited
        case 500, 502, 503: throw CorrectionError.serverTimeout
        default:         throw CorrectionError.outputParsingFailed(raw: "HTTP \(statusCode)")
        }
    }

    nonisolated var resolvedLanguage: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    func resolveStyle() async -> String {
        let ctx = await ContextStorage.shared.current
        // High-confidence context (usually from app bundle ID) → always trust it.
        if let ctx, ctx.confidence >= 0.80 {
            return ctx.style.promptEngineStyle
        }
        // Medium-confidence context: only trust if style is not neutral.
        if let ctx, ctx.confidence >= 0.55, ctx.style != .neutral {
            return ctx.style.promptEngineStyle
        }
        return "equilibrato"
    }

    private func maxTokens(for text: String, isFluency: Bool) -> Int {
        // text.count is characters; ~4 chars/token for Latin, so divide by 4.
        // CJK is ~1.5 chars/token — this formula underestimates, which is safe (generous output).
        let approxInputTokens = max(64, text.count / 4)
        return isFluency
            ? max(256, min(approxInputTokens * 2 + 128, 2048))
            : max(256, min(approxInputTokens + approxInputTokens / 4 + 64, 2048))
    }

    private func buildChatBody(
        text: String,
        promptType: PromptType,
        engine: PromptEngine,
        model: String,
        temperatureOffset: Double = 0
    ) -> ChatRequest {
        let prompt: String
        let temperature: Double
        switch promptType {
        case .fluency:
            prompt = engine.buildFluencyPrompt(for: text, customInstruction: nil)
            temperature = Constants.fluencyTemperature + temperatureOffset
        default:
            prompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)
            temperature = Constants.grammarTemperature + temperatureOffset
        }
        return chatBody(model: model, prompt: prompt, temperature: temperature,
                        maxTokens: maxTokens(for: text, isFluency: promptType.isFluency))
    }

    func performCorrection(
        text: String,
        promptType: PromptType,
        language: String = "",
        model: String,
        url: URL,
        apiKey: String?,
        extraHeaders: [String: String] = [:]
    ) async throws -> CorrectionResult {
        CrashLogger.log("performCorrection: start model=\(model) type=\(promptType.label)")
        let lang = language.isEmpty
            ? LanguageDetector.detect(text: text, fallbackLanguage: resolvedLanguage)
            : language
        let engine = PromptEngine(language: lang, style: await resolveStyle())
        let rawCorrected = try await performOpenAIRequest(
            body: buildChatBody(text: text, promptType: promptType, engine: engine, model: model),
            url: url, apiKey: apiKey, extraHeaders: extraHeaders
        )
        CrashLogger.log("performCorrection: done")
        let corrected = validateCorrection(original: text, corrected: rawCorrected, isFluency: promptType.isFluency)
        return CorrectionResult(
            original: text, corrected: corrected,
            modelID: model, confidence: Constants.defaultConfidence, promptType: promptType.label
        )
    }

    func validateCorrection(original: String, corrected: String, isFluency: Bool = false) -> String {
        var text = corrected.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip known completion primers that the model might echo
        let stripPrefixes = ["output:", "corrected:", "testo corretto:", "texte corrigé:", "corrección:",
                             "rewritten:", "testo riscritto:", "texte réécrit:"]
        let lower = text.lowercased()
        for prefix in stripPrefixes {
            if lower.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        // Strip wrapping quotes added by some models
        if let q = text.first, (q == "\"" || q == "'"), text.last == q, text.count > 2 {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // If the model appended an explanation after a blank line, strip it.
        // Only truncate if the text after the blank line looks like meta-commentary —
        // NOT if it looks like a legitimate second paragraph of a multi-paragraph correction.
        if let blankLine = text.range(of: "\n\n") {
            let afterBreak = String(text[blankLine.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let commentaryMarkers = [
                "note:", "notes:", "correction:", "corrections:", "change:", "changes:",
                "explanation:", "i've ", "i have ", "here's ", "here is ", "the following",
                "i corrected", "i fixed", "i changed",
                "nota:", "note che", "ho corretto", "correzioni:", "spiegazione:",
                "j'ai ", "voici ", "j'ai corrigé",
                "ich habe ", "hier ist", "korrektur:",
                "he corregido", "aquí está",
            ]
            let looksLikeCommentary = commentaryMarkers.contains(where: { afterBreak.hasPrefix($0) })
            if looksLikeCommentary {
                let firstBlock = String(text[..<blankLine.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !firstBlock.isEmpty { text = firstBlock }
            }
        }

        // Sanity: if output is empty, return original
        if text.isEmpty { return original }
        // Fluency rewrites can be up to 6x longer (combining short sentences); grammar up to 4x
        let maxRatio = isFluency ? 6 : 4
        if text.count > original.count * maxRatio { return original }

        // Sanity: if output looks like it's still just instructions, return original
        let chattyPhrases = [
            "here's the corrected", "here is the corrected", "corrected text:",
            "corrected version:", "edited text:", "sure, here", "i have corrected",
            "here's the rewritten", "here is the rewritten", "rewritten text:",
            "ecco il testo", "voici le texte", "hier ist der korrigierte",
            "aquí está el texto", "texto corregido:",
        ]
        let lowerText = text.lowercased()
        if chattyPhrases.contains(where: { lowerText.hasPrefix($0) }) { return original }

        // For grammar mode: if more than 50% of tokens differ, the model over-corrected —
        // fall back to original rather than presenting a hallucinated rewrite.
        if !isFluency && wordChangeFraction(original: original, corrected: text) > 0.5 {
            return original
        }

        return isFluency ? text : preservePunctuation(original: original, corrected: text)
    }

    private func wordChangeFraction(original: String, corrected: String) -> Double {
        // Tokenize by whitespace; CJK texts fall back to character-level comparison.
        let origTokens = original.split(separator: " ").map(String.init)
        let corrTokens = corrected.split(separator: " ").map(String.init)
        guard !origTokens.isEmpty else { return 0 }
        // Use a simple set-difference approach: tokens present in original but not corrected.
        let origSet = Set(origTokens.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) })
        let corrSet = Set(corrTokens.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) })
        let removed = origSet.subtracting(corrSet).count
        return Double(removed) / Double(origSet.count)
    }

    private func preservePunctuation(original: String, corrected: String) -> String {
        let punctChars = CharacterSet(charactersIn: ".!?;:")
        let trimmedCorrected = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let origLast = original.trimmingCharacters(in: .whitespacesAndNewlines).last,
              let corrLast = trimmedCorrected.last,
              origLast != corrLast,
              let origScalar = origLast.unicodeScalars.first,
              let corrScalar = corrLast.unicodeScalars.first,
              punctChars.contains(origScalar),
              !punctChars.contains(corrScalar) else {
            return corrected
        }
        return trimmedCorrected + String(origLast)
    }

    func chatBody(
        model: String,
        prompt: String,
        systemPrompt: String? = "You are a text corrector. Output ONLY the corrected text in the same language as the input. Do not translate. Do not explain. Do not add context. Do not respond conversationally. Do not use prefixes like 'Here is the corrected text:'. Do not wrap the output in quotes. Preserve original punctuation and formatting. Output ONLY the corrected text, nothing else.",
        temperature: Double,
        maxTokens: Int = 1024,
        stream: Bool = false
    ) -> ChatRequest {
        var messages: [ChatMessage]
        if let sys = systemPrompt {
            messages = [ChatMessage(role: "system", content: sys), ChatMessage(role: "user", content: prompt)]
        } else {
            messages = [ChatMessage(role: "user", content: prompt)]
        }
        return ChatRequest(model: model, messages: messages, temperature: temperature,
                           max_tokens: maxTokens, stream: stream)
    }

    // MARK: - Shared streaming (used by all concrete services)

    func defaultStreamCorrect(
        text: String,
        promptType: PromptType,
        model: String,
        url: URL,
        apiKey: String?,
        extraHeaders: [String: String] = [:]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let lang = LanguageDetector.detect(text: text, fallbackLanguage: resolvedLanguage)
                    let engine = PromptEngine(language: lang, style: await resolveStyle())
                    let prompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)
                    let body = chatBody(model: model, prompt: prompt, temperature: 0.1, stream: true)
                    var request = try buildLLMRequest(url: url, apiKey: apiKey, body: body)
                    for (key, value) in extraHeaders {
                        request.setValue(value, forHTTPHeaderField: key)
                    }
                    for try await accumulated in await SSEStreamingEngine.shared.stream(request: request) {
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
