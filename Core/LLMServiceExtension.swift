import Foundation
import os

// MARK: - Utility condivisa (tutti i servizi LLM)

extension LLMService {

    func parseResponse(data: Data) throws -> String {
        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CorrectionError.outputParsingFailed(raw: String(data: data, encoding: .utf8) ?? "nil")
            }
            json = parsed
        } catch is CorrectionError {
            throw CorrectionError.outputParsingFailed(raw: String(data: data, encoding: .utf8) ?? "nil")
        } catch {
            throw CorrectionError.outputParsingFailed(raw: String(data: data, encoding: .utf8) ?? error.localizedDescription)
        }
        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw CorrectionError.outputParsingFailed(raw: String(data: data, encoding: .utf8) ?? "nil")
        }
        var cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip prefissi chatbot comuni nei modelli piccoli
        let chattyPrefixes = [
            "Here's the corrected text:",
            "Here is the corrected text:",
            "Corrected text:",
            "Edited text:",
            "Sure, here's the corrected version:",
            "Here's the edited version:",
            "Ecco il testo corretto:",
            "Testo corretto:",
            "Ecco la versione corretta:",
        ]
        for prefix in chattyPrefixes {
            if cleaned.lowercased().hasPrefix(prefix.lowercased()) {
                cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        // Strip virgolette wrapper aggiunte dal modello (es: "testo corretto")
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count > 2 {
            cleaned = String(cleaned.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }

    func buildLLMRequest(url: URL, apiKey: String?, body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Constants.requestTimeout
        if let key = apiKey {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func performOpenAIRequest(
        body: [String: Any],
        url: URL,
        apiKey: String?,
        extraHeaders: [String: String] = [:]
    ) async throws -> String {
        try throwIfInvalidLLMURL(url)
        // Cache check (solo richieste non-stream)
        if let prompt = (body["messages"] as? [[String: String]])?.last(where: { $0["role"] == "user" })?["content"],
           let model = body["model"] as? String,
           let cached = ResponseCache.shared.get(text: prompt, model: model, promptType: "request") {
            return cached
        }
        var request = try buildLLMRequest(url: url, apiKey: apiKey, body: body)
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        var lastError: Error?
        for attempt in 0..<Constants.maxRetries {
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
                if let prompt = (body["messages"] as? [[String: String]])?.last(where: { $0["role"] == "user" })?["content"],
                   let model = body["model"] as? String {
                    ResponseCache.shared.set(text: prompt, model: model, promptType: "request", result: result)
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
            guard attempt < Constants.maxRetries - 1 else { break }
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
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.language) ?? "it"
    }

    nonisolated var resolvedStyle: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.style) ?? "equilibrato"
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

    private func performCorrectionAlternative(
        text: String,
        promptType: PromptType,
        model: String,
        url: URL,
        apiKey: String?,
        extraHeaders: [String: String] = [:]
    ) async throws -> CorrectionResult {
        let engine = PromptEngine(language: resolvedLanguage, style: resolvedStyle)
        let prompt: String
        let temperature: Double
        switch promptType {
        case .fluency:
            prompt = engine.buildFluencyPrompt(for: text, customInstruction: nil)
            temperature = Constants.fluencyTemperature + 0.1
        default:
            prompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)
            temperature = Constants.grammarTemperature + 0.1
        }
        let maxTokens = max(128, min(text.count + 100, 512))
        let rawCorrected = try await performOpenAIRequest(
            body: chatBody(model: model, prompt: prompt, temperature: temperature, maxTokens: maxTokens),
            url: url, apiKey: apiKey, extraHeaders: extraHeaders
        )
        let corrected = validateCorrection(original: text, corrected: rawCorrected)
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
        let engine = PromptEngine(language: resolvedLanguage, style: resolvedStyle)
        let prompt: String
        let temperature: Double
        switch promptType {
        case .fluency:
            prompt = engine.buildFluencyPrompt(for: text, customInstruction: nil)
            temperature = Constants.fluencyTemperature
        default:
            prompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)
            temperature = Constants.grammarTemperature
        }
        let maxTokens = max(128, min(text.count + 100, 512))
        let rawCorrected = try await performOpenAIRequest(
            body: chatBody(model: model, prompt: prompt, temperature: temperature, maxTokens: maxTokens),
            url: url, apiKey: apiKey, extraHeaders: extraHeaders
        )
        let corrected = validateCorrection(original: text, corrected: rawCorrected)
        return CorrectionResult(
            original: text, corrected: corrected,
            modelID: model, confidence: Constants.defaultConfidence, promptType: promptType.label
        )
    }

    func validateCorrection(original: String, corrected: String) -> String {
        // 1. Se corrected è 3x+ più lungo dell'originale -> il modello ha aggiunto testo non richiesto
        if corrected.count > original.count * 3 {
            return original
        }
        // 2. Se corrected inizia con prefissi chatbot rimasti dopo 0.1 (double-check)
        let chattyPrefixes = ["Here", "Sure", "The corrected", "Ecco", "Il testo"]
        if chattyPrefixes.contains(where: { corrected.hasPrefix($0) }) && !original.hasPrefix(corrected.prefix(4)) {
            return original
        }
        // 3. Se corrected è la stessa stringa dell'originale racchiusa in virgolette
        let stripped = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.hasPrefix("\"") && stripped.hasSuffix("\"") {
            let inner = String(stripped.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if inner == original { return original }
        }
        // 4. Preserva punteggiatura finale dell'originale se corrected la cambia
        return preservePunctuation(original: original, corrected: corrected)
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
        systemPrompt: String? = "Sei un correttore di testi. Riscrivi SOLO il testo corretto, nella stessa lingua dell'input. Non tradurre. Non spiegare. Non aggiungere contesto. Non rispondere in modo conversazionale. Non usare prefissi come 'Here's the corrected text:'. Non racchiudere il testo in virgolette. Preserva la punteggiatura originale. Scrivi esclusivamente il testo corretto, nessun'altra parola.",
        temperature: Double,
        maxTokens: Int = 1024,
        stream: Bool = false
    ) -> [String: Any] {
        var messages: [[String: String]]
        if let sys = systemPrompt {
            messages = [["role": "system", "content": sys], ["role": "user", "content": prompt]]
        } else {
            messages = [["role": "user", "content": prompt]]
        }
        return ["model": model, "messages": messages, "temperature": temperature,
                "max_tokens": maxTokens, "stream": stream]
    }

    func performOpenAIStreamRequest(
        body: [String: Any],
        url: URL,
        apiKey: String?,
        extraHeaders: [String: String] = [:]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let session = URLSession(configuration: .default)
                defer { session.invalidateAndCancel() }
                do {
                    var streamBody = body
                    streamBody["stream"] = true
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
                                os_log(.debug, "Stream: unparseable chunk (%d)", skippedChunks)
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

// MARK: - Implementazioni default per LLMServiceBase

extension LLMServiceBase {

    func correct(text: String, promptType: PromptType) async throws -> CorrectionResult {
        let url = try await resolveURL()
        let apiKey = try await resolveAPIKey()
        return try await performCorrection(
            text: text, promptType: promptType,
            model: resolvedModel, url: url, apiKey: apiKey, extraHeaders: extraServiceHeaders
        )
    }

    func correctFluency(text: String) async throws -> CorrectionResult {
        let url = try await resolveURL()
        let apiKey = try await resolveAPIKey()
        return try await performCorrection(
            text: text, promptType: .fluency,
            model: resolvedModel, url: url, apiKey: apiKey, extraHeaders: extraServiceHeaders
        )
    }

    func explain(original: String, corrected: String) async throws -> String {
        let engine = PromptEngine(language: resolvedLanguage, style: resolvedStyle)
        let prompt = engine.buildExplainPrompt(original: original, corrected: corrected, customInstruction: nil)
        let url = try await resolveURL()
        let apiKey = try await resolveAPIKey()
        return try await performOpenAIRequest(
            body: chatBody(model: resolvedModel, prompt: prompt, systemPrompt: nil,
                           temperature: Constants.fluencyTemperature, maxTokens: Constants.explainMaxTokens),
            url: url, apiKey: apiKey, extraHeaders: extraServiceHeaders
        )
    }

    func streamCorrect(text: String, promptType: PromptType) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let engine = PromptEngine(language: self.resolvedLanguage, style: self.resolvedStyle)
                    let prompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)
                    let url = try await self.resolveURL()
                    let apiKey = try await self.resolveAPIKey()
                    let maxTokens = max(128, min(text.count + 100, 512))
                    let temperature = promptType.label == "fluency" ? Constants.fluencyTemperature : Constants.grammarTemperature
                    let stream = self.performOpenAIStreamRequest(
                        body: self.chatBody(model: self.resolvedModel, prompt: prompt, temperature: temperature, maxTokens: maxTokens, stream: true),
                        url: url, apiKey: apiKey, extraHeaders: self.extraServiceHeaders
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
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
