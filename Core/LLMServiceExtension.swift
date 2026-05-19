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
        let userPrompt = body.messages.last(where: { $0.role == "user" })?.content
        if let prompt = userPrompt,
           let cached = ResponseCache.shared.get(text: prompt, model: body.model, promptType: "request") {
            return cached
        }
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
                if let prompt = userPrompt {
                    ResponseCache.shared.set(text: prompt, model: body.model, promptType: "request", result: result)
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
        if let ctx = await ContextStorage.shared.current, ctx.confidence >= 0.60 {
            return ctx.style.promptEngineStyle
        }
        return "equilibrato"
    }

    func rankedCorrection(
        text: String,
        promptType: PromptType,
        model: String,
        url: URL,
        apiKey: String?,
        extraHeaders: [String: String] = [:]
    ) async throws -> CorrectionResult {
        async let r1 = performCorrection(text: text, promptType: promptType, model: model, url: url, apiKey: apiKey, extraHeaders: extraHeaders)
        async let r2 = performCorrectionAlternative(text: text, promptType: promptType, model: model, url: url, apiKey: apiKey, extraHeaders: extraHeaders)
        let results = try await [r1, r2]
        guard let best = results.max(by: { ($0.confidence ?? 0) < ($1.confidence ?? 0) }) else {
            return results[0]
        }
        return best
    }

    private func maxTokens(for text: String, isFluency: Bool) -> Int {
        isFluency
            ? max(256, min(text.count * 2, 1024))
            : max(128, min(text.count + 100, 512))
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

    private func performCorrectionAlternative(
        text: String,
        promptType: PromptType,
        model: String,
        url: URL,
        apiKey: String?,
        extraHeaders: [String: String] = [:]
    ) async throws -> CorrectionResult {
        let detectedLang = LanguageDetector.detect(text: text, fallbackLanguage: resolvedLanguage)
        let engine = PromptEngine(language: detectedLang, style: await resolveStyle())
        let rawCorrected = try await performOpenAIRequest(
            body: buildChatBody(text: text, promptType: promptType, engine: engine, model: model, temperatureOffset: 0.1),
            url: url, apiKey: apiKey, extraHeaders: extraHeaders
        )
        let corrected = validateCorrection(original: text, corrected: rawCorrected, isFluency: promptType.isFluency)
        let confidence = corrected == text ? 0.5 : 0.85
        return CorrectionResult(
            original: text, corrected: corrected,
            modelID: model, confidence: confidence, promptType: promptType.label
        )
    }

    func performCorrection(
        text: String,
        promptType: PromptType,
        model: String,
        url: URL,
        apiKey: String?,
        extraHeaders: [String: String] = [:]
    ) async throws -> CorrectionResult {
        let detectedLang = LanguageDetector.detect(text: text, fallbackLanguage: resolvedLanguage)
        let engine = PromptEngine(language: detectedLang, style: await resolveStyle())
        let rawCorrected = try await performOpenAIRequest(
            body: buildChatBody(text: text, promptType: promptType, engine: engine, model: model),
            url: url, apiKey: apiKey, extraHeaders: extraHeaders
        )
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
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }

        // If the model added explanations after the corrected text (blank line separator), take only the first block
        if let blankLine = text.range(of: "\n\n") {
            let firstBlock = String(text[..<blankLine.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            // For fluency, allow slightly longer first block (rewrites can expand sentences)
            let maxRatio = isFluency ? 3 : 2
            if !firstBlock.isEmpty && firstBlock.count <= original.count * maxRatio {
                text = firstBlock
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

        return isFluency ? text : preservePunctuation(original: original, corrected: text)
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

    func performOpenAIStreamRequest(
        body: ChatRequest,
        url: URL,
        apiKey: String?,
        extraHeaders: [String: String] = [:]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let session = URLSession(configuration: .default)
                defer { session.invalidateAndCancel() }
                do {
                    let streamBody = ChatRequest(model: body.model, messages: body.messages,
                                                temperature: body.temperature, max_tokens: body.max_tokens,
                                                stream: true)
                    var request = try buildLLMRequest(url: url, apiKey: apiKey, body: streamBody)
                    for (key, value) in extraHeaders {
                        request.setValue(value, forHTTPHeaderField: key)
                    }
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw CorrectionError.networkUnavailable
                    }
                    try handleOpenAIHTTPStatus(httpResponse.statusCode, data: Data())

                    var skippedChunks = 0
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))
                        if jsonStr == "[DONE]" { continuation.finish(); return }
                        guard let jsonData = jsonStr.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let first = choices.first,
                              let delta = first["delta"] as? [String: Any],
                              let content = delta["content"] as? String else {
                            if !jsonStr.isEmpty && jsonStr != "[DONE]" {
                                skippedChunks += 1
                                Logger.core.debug("Stream: unparseable chunk (\(skippedChunks, privacy: .public))")
                            }
                            continue
                        }
                        continuation.yield(content)
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
