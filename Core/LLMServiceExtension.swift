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

    private func maxTokens(for text: String, promptType: PromptType) -> Int {
        let approxInputTokens = max(64, text.count / 4)
        switch promptType {
        case .fluency, .translation:
            return max(256, min(approxInputTokens * 2 + 128, 2048))
        case .coach, .explain:
            return max(512, min(approxInputTokens * 3 + 256, 2048))
        default:
            return max(256, min(approxInputTokens + approxInputTokens / 4 + 64, 2048))
        }
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
        let systemPrompt: String?

        switch promptType {
        case .grammar:
            prompt = engine.buildGrammarPrompt(for: text, customInstruction: nil)
            temperature = Constants.grammarTemperature + temperatureOffset
            systemPrompt = "You are a proofreader. Fix ONLY clear grammatical errors: misspellings, wrong verb forms, wrong agreement, missing required grammatical forms. ABSOLUTE RULES: (1) Every grammatically correct word MUST be kept unchanged. (2) Do NOT add any word, fact, or information not in the original text. (3) Preserve sentence type exactly — a statement ends with a period and stays a statement, a question ends with a question mark and stays a question. (4) Do NOT rephrase, reorder, or substitute synonyms. (5) Output must be in the SAME language as the input — do NOT translate. (6) If no errors exist, output the text VERBATIM. Output ONLY the corrected text — no labels, no explanations, no quotes."
        case .fluency:
            prompt = engine.buildFluencyPrompt(for: text, customInstruction: nil)
            temperature = Constants.fluencyTemperature + temperatureOffset
            systemPrompt = "You are a writing assistant. Rewrite text to improve readability, flow, and naturalness. Preserve the original meaning exactly — do not add, invent, or assume any information not in the original. Output only the rewritten text. Keep the exact same language as the input — do NOT translate to English or any other language."
        case .grammarAndFluency:
            prompt = engine.buildCombinedPrompt(for: text)
            temperature = (Constants.grammarTemperature + Constants.fluencyTemperature) / 2.0 + temperatureOffset
            systemPrompt = "You are a proofreader and writing assistant. Fix all grammatical errors AND improve fluency and flow. Preserve the original meaning exactly — do NOT add facts or information not in the original. Preserve sentence type (statement/question/exclamation). Output must be in the SAME language as the input. Do NOT translate. Output only the corrected text."
        case .coach:
            prompt = engine.buildCoachPrompt(for: text)
            temperature = Constants.grammarTemperature + temperatureOffset
            systemPrompt = "You are a concise writing coach. Analyze only the specific text given — never invent issues that are not present. Respond in the same language as the input text."
        case .deSlop:
            prompt = engine.buildDeSlopPrompt(for: text)
            temperature = Constants.fluencyTemperature + temperatureOffset
            systemPrompt = "You are an editor. Remove AI-sounding patterns from text. Preserve meaning. Output only the rewritten text in the same language as the input — do NOT translate."
        case .aiPrompt:
            prompt = engine.buildAIPromptPrompt(for: text)
            temperature = Constants.grammarTemperature + temperatureOffset
            systemPrompt = "You are a prompt engineer. Rewrite the given text into an effective AI assistant prompt. Output only the optimized prompt."
        case .expand:
            prompt = engine.buildExpandPrompt(for: text, contactProfile: nil)
            temperature = Constants.fluencyTemperature + temperatureOffset
            systemPrompt = "You are an expert writing assistant. Expand rough draft notes into a complete, polished message. Output only the final message — no preamble, no explanation."
        default:
            // Translation, explain, custom: no system prompt — user prompt fully specifies the task.
            prompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)
            temperature = Constants.grammarTemperature + temperatureOffset
            systemPrompt = nil
        }
        return chatBody(model: model, prompt: prompt, systemPrompt: systemPrompt,
                        temperature: temperature,
                        maxTokens: maxTokens(for: text, promptType: promptType))
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
        let corrected: String
        switch promptType {
        case .grammar, .fluency, .grammarAndFluency, .deSlop:
            let isFluency = promptType != .grammar
            corrected = validateCorrection(original: text, corrected: rawCorrected, isFluency: isFluency)
        default:
            corrected = rawCorrected.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return CorrectionResult(
            original: text, corrected: corrected,
            modelID: model, confidence: Constants.defaultConfidence, promptType: promptType.label
        )
    }

    func validateCorrection(original: String, corrected: String, isFluency: Bool = false) -> String {
        var text = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return original }

        // 1. Strip label prefixes — language-agnostic structural detection.
        //    Models sometimes output "Corrected text: ...", "Testo corretto: ...", "修正後: ..." etc.
        //    Pattern: up to 3 tokens before the first ":" with no newline → strip the label.
        let firstLine = String(text.prefix(while: { $0 != "\n" }))
        if let colonIdx = firstLine.firstIndex(of: ":") {
            let labelPart = String(firstLine[..<colonIdx]).trimmingCharacters(in: .whitespaces)
            let labelWords = labelPart.split(whereSeparator: \.isWhitespace).count
            if labelWords <= 3 && !labelPart.isEmpty {
                let origLower = original.lowercased()
                let labelLower = labelPart.lowercased()
                // Only strip if the label word is not part of the original text
                if !origLower.contains(labelLower) {
                    let after = String(text[text.index(after: colonIdx)...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !after.isEmpty && after.count >= original.count / 4 { text = after }
                }
            }
        }

        // 2. Strip wrapping quotes
        if let q = text.first, (q == "\"" || q == "'"), text.last == q, text.count > 2 {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 3. Strip appended commentary after a blank line — language-agnostic structural check.
        //    If the first block is ≥50% the length of the original (a substantial correction)
        //    AND the second block is less than half the length of the first block,
        //    the second block is almost certainly meta-commentary, not a second paragraph.
        if let blankRange = text.range(of: "\n\n") {
            let firstBlock = String(text[..<blankRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let secondBlock = String(text[blankRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let firstCoversOriginal = Double(firstBlock.count) / Double(max(original.count, 1)) >= 0.5
            let secondMuchShorter = secondBlock.count < firstBlock.count / 2
            if firstCoversOriginal && secondMuchShorter && !firstBlock.isEmpty {
                text = firstBlock
            }
        }

        guard !text.isEmpty else { return original }

        // 4. Language drift: if detected language changed, the model accidentally translated — reject.
        //    Only check when both strings are long enough for reliable detection.
        if text.count >= 25 && original.count >= 25 {
            let origLang = LanguageDetector.detect(text: original, fallbackLanguage: "")
            let corrLang = LanguageDetector.detect(text: text, fallbackLanguage: "")
            if !origLang.isEmpty && !corrLang.isEmpty && origLang != corrLang {
                return original
            }
        }

        // 5. Length sanity: grammar up to 2x (should not expand significantly), fluency up to 6x
        let maxRatio = isFluency ? 6 : 2
        if text.count > original.count * maxRatio { return original }

        // 6. For grammar: reject if >50% of words differ (over-correction / invented content)
        if !isFluency && wordChangeFraction(original: original, corrected: text) > 0.50 {
            return original
        }

        return isFluency ? text : preservePunctuation(original: original, corrected: text)
    }

    private func wordChangeFraction(original: String, corrected: String) -> Double {
        let origTokens = original.split(separator: " ")
            .map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        let corrTokens = corrected.split(separator: " ")
            .map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        guard !origTokens.isEmpty else { return 0 }
        // Count how many original tokens have no match in corrected (multiset-aware).
        var corrCounts = corrTokens.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        var unmatched = 0
        for tok in origTokens {
            if let n = corrCounts[tok], n > 0 {
                corrCounts[tok] = n - 1
            } else {
                unmatched += 1
            }
        }
        return Double(unmatched) / Double(origTokens.count)
    }

    private func preservePunctuation(original: String, corrected: String) -> String {
        let sentenceEnders = CharacterSet(charactersIn: ".!?")
        let allPunct = CharacterSet(charactersIn: ".!?;:")
        let trimmedCorrected = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let origLast = original.trimmingCharacters(in: .whitespacesAndNewlines).last,
              origLast != trimmedCorrected.last,
              let origScalar = origLast.unicodeScalars.first,
              sentenceEnders.contains(origScalar)
        else { return corrected }
        // Model changed punctuation type (e.g., "." → "?") — replace last char with original.
        if let corrLast = trimmedCorrected.last,
           let corrScalar = corrLast.unicodeScalars.first,
           allPunct.contains(corrScalar) {
            return String(trimmedCorrected.dropLast()) + String(origLast)
        }
        // Model removed final punctuation — restore it.
        return trimmedCorrected + String(origLast)
    }

    func chatBody(
        model: String,
        prompt: String,
        systemPrompt: String? = "You are a proofreader. Fix only clear grammatical errors: misspellings, wrong verb forms, wrong agreement. Do NOT add information, do NOT change sentence type, do NOT rephrase, do NOT translate. Output only the corrected text.",
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

// MARK: - Structured JSON output

enum LLMJSONParser {
    private struct GrammarJSON: Codable {
        struct Correction: Codable {
            let original: String
            let replacement: String
            let reason: String
        }
        let corrections: [Correction]
    }

    static func parse(json: String, in text: String) -> [CorrectionSpan] {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(GrammarJSON.self, from: data)
        else { return [] }
        var spans: [CorrectionSpan] = []
        for correction in parsed.corrections {
            guard correction.original != correction.replacement,
                  !correction.original.isEmpty,
                  let range = text.range(of: correction.original)
            else { continue }
            spans.append(CorrectionSpan(
                range: NSRange(range, in: text),
                original: correction.original,
                replacement: correction.replacement,
                reason: correction.reason,
                confidence: 0.85,
                source: .llm))
        }
        return spans.sorted { $0.range.location < $1.range.location }
    }

    static func cleanAndParse(json: String, in text: String) -> [CorrectionSpan] {
        var cleaned = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            let lines = cleaned.components(separatedBy: "\n")
            cleaned = lines.dropFirst().joined(separator: "\n")
            if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        }
        return parse(json: cleaned.trimmingCharacters(in: .whitespacesAndNewlines), in: text)
    }
}
