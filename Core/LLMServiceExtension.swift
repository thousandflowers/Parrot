import Foundation
import OSLog
import NaturalLanguage

// MARK: - Utility condivisa (tutti i servizi LLM)

/// Per-request prompt context, carried as task-locals so it reaches every concrete
/// service's `correct` without changing the `LLMService` protocol (and all its conformers).
/// RequestQueue binds these around the service call for exactly one request.
enum PromptContext {
    /// Extra instruction appended to the real prompt (e.g. knowledge-base reference context).
    /// It never replaces the prompt: the user's text is always sent.
    @TaskLocal static var extraInstruction: String?
    /// Model to use instead of the one configured in Settings (fallback-model retry).
    @TaskLocal static var modelOverride: String?
}

struct ParsedChatResponse: Equatable {
    let content: String
    /// The server stopped at max_tokens (`finish_reason == "length"`): the text is cut off.
    let isTruncated: Bool
}

extension LLMService {

    func parseResponse(data: Data) throws -> String {
        try parseChatResponse(data: data).content
    }

    func parseChatResponse(data: Data) throws -> ParsedChatResponse {
        let raw = String(data: data, encoding: .utf8) ?? "nil"
        let response: ChatResponse
        do {
            response = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw CorrectionError.outputParsingFailed(raw: raw)
        }
        guard let choice = response.choices.first, !choice.message.content.isEmpty else {
            throw CorrectionError.outputParsingFailed(raw: raw)
        }
        return ParsedChatResponse(
            content: choice.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
            isTruncated: choice.finish_reason == "length"
        )
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
        extraHeaders: [String: String] = [:],
        rejectTruncated: Bool = false
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
                let parsed = try parseChatResponse(data: data)
                guard !parsed.content.isEmpty else {
                    throw CorrectionError.outputParsingFailed(raw: "empty")
                }
                // A grammar/fluency correction cut off at max_tokens would silently delete
                // the tail of the user's text on replace — never accept it.
                if rejectTruncated && parsed.isTruncated {
                    throw CorrectionError.outputParsingFailed(raw: "truncated (finish_reason=length)")
                }
                return parsed.content
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
        guard let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty else {
            throw CorrectionError.networkUnavailable
        }
        // Plain http only to loopback — otherwise the user's text and Bearer key
        // would go cleartext to an arbitrary host. Everything else must be https.
        let loopback: Set<String> = ["localhost", "127.0.0.1", "::1"]
        guard scheme == "https" || (scheme == "http" && loopback.contains(host.lowercased())) else {
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
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.language)
            ?? Locale.current.language.languageCode?.identifier ?? "en"
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
        let approxInputTokens = max(64, TokenEstimator.estimatedTokens(for: text))
        switch promptType {
        case .fluency, .translation:
            return max(256, min(approxInputTokens * 2 + 128, 2048))
        case .coach, .explain:
            return max(512, min(approxInputTokens * 3 + 256, 2048))
        default:
            return max(256, min(approxInputTokens + approxInputTokens / 4 + 64, 2048))
        }
    }

    /// Prompt, system prompt and base temperature for one prompt type. Shared by the
    /// one-shot and the streaming path so both send the same task to the model.
    /// `extraInstruction` (e.g. knowledge-base context) is ADDED to the real prompt.
    func promptPlan(
        text: String,
        promptType: PromptType,
        engine: PromptEngine,
        extraInstruction: String?
    ) -> (prompt: String, systemPrompt: String?, temperature: Double) {
        let extra = extraInstruction.flatMap { $0.isEmpty ? nil : $0 }
        // Builders that take a custom instruction get it inline; the others get it in the
        // system prompt (or as a leading block when there is none).
        func withContext(_ system: String?) -> String? {
            guard let extra else { return system }
            return system.map { $0 + "\n\n" + extra } ?? extra
        }
        switch promptType {
        case .grammar:
            return (engine.buildGrammarPrompt(for: text, customInstruction: extra),
                    "You are a proofreader. Fix ONLY clear grammatical errors: misspellings, wrong verb forms, wrong agreement, missing required grammatical forms. ABSOLUTE RULES: (1) Every grammatically correct word MUST be kept unchanged. (2) Do NOT add any word, fact, or information not in the original text. (3) Preserve sentence type exactly — a statement ends with a period and stays a statement, a question ends with a question mark and stays a question. (4) Do NOT rephrase, reorder, or substitute synonyms. (5) Output must be in the SAME language as the input — do NOT translate. (6) If no errors exist, output the text VERBATIM. Output ONLY the corrected text — no labels, no explanations, no quotes.",
                    Constants.grammarTemperature)
        case .fluency:
            return (engine.buildFluencyPrompt(for: text, customInstruction: extra),
                    "You are a writing assistant. Rewrite text to improve readability, flow, and naturalness. Preserve the original meaning exactly — do not add, invent, or assume any information not in the original. Output only the rewritten text. Keep the exact same language as the input — do NOT translate to English or any other language.",
                    Constants.fluencyTemperature)
        case .grammarAndFluency:
            return (engine.buildCombinedPrompt(for: text),
                    withContext("You are a proofreader and writing assistant. Fix all grammatical errors AND improve fluency and flow. Preserve the original meaning exactly — do NOT add facts or information not in the original. Preserve sentence type (statement/question/exclamation). Output must be in the SAME language as the input. Do NOT translate. Output only the corrected text."),
                    (Constants.grammarTemperature + Constants.fluencyTemperature) / 2.0)
        case .coach:
            return (engine.buildCoachPrompt(for: text),
                    withContext("You are a concise writing coach. Analyze only the specific text given — never invent issues that are not present. Respond in the same language as the input text."),
                    Constants.grammarTemperature)
        case .deSlop:
            return (engine.buildDeSlopPrompt(for: text),
                    withContext("You are an editor. Remove AI-sounding patterns from text. Preserve meaning. Output only the rewritten text in the same language as the input — do NOT translate."),
                    Constants.fluencyTemperature)
        case .aiPrompt:
            return (engine.buildAIPromptPrompt(for: text),
                    withContext("You are a prompt engineer. Rewrite the given text into an effective AI assistant prompt. Output only the optimized prompt."),
                    Constants.grammarTemperature)
        case .expand:
            return (engine.buildExpandPrompt(for: text, contactProfile: nil),
                    withContext("You are an expert writing assistant. Expand rough draft notes into a complete, polished message. Output only the final message — no preamble, no explanation."),
                    Constants.fluencyTemperature)
        case .custom:
            // The user's template fully specifies the task; context goes in its <CUSTOM> slot.
            return (engine.buildPrompt(for: text, type: promptType, customInstruction: extra), nil,
                    Constants.grammarTemperature)
        default:
            // Translation, explain: no system prompt — user prompt fully specifies the task.
            return (engine.buildPrompt(for: text, type: promptType, customInstruction: nil), withContext(nil),
                    Constants.grammarTemperature)
        }
    }

    private func buildChatBody(
        text: String,
        promptType: PromptType,
        engine: PromptEngine,
        model: String,
        temperatureOffset: Double = 0,
        sampling: SamplingParams? = nil,
        seedOverride: Int? = nil,
        stream: Bool = false
    ) -> ChatRequest {
        let plan = promptPlan(text: text, promptType: promptType, engine: engine,
                              extraInstruction: PromptContext.extraInstruction)
        var effectiveSampling = sampling
        if let seedOverride { effectiveSampling?.seed = seedOverride }
        return chatBody(model: model, prompt: plan.prompt, systemPrompt: plan.systemPrompt,
                        temperature: plan.temperature + temperatureOffset,
                        maxTokens: maxTokens(for: text, promptType: promptType),
                        stream: stream,
                        sampling: effectiveSampling)
    }

    /// Cleans and validates one raw model output into a final correction string.
    /// Every backend (HTTP, MLX, Apple Intelligence, streaming) must go through this.
    func postProcess(raw: String, text: String, promptType: PromptType, lang: String) -> String {
        CorrectionSanitizer.postProcess(raw: raw, original: text, promptType: promptType, language: lang)
    }

    /// Grammar/fluency must never accept output cut off at max_tokens.
    private func rejectsTruncation(_ promptType: PromptType) -> Bool {
        switch promptType {
        case .grammar, .fluency, .grammarAndFluency: return true
        default: return false
        }
    }

    func performCorrection(
        text: String,
        promptType: PromptType,
        language: String = "",
        model: String,
        url: URL,
        apiKey: String?,
        extraHeaders: [String: String] = [:],
        sampling: SamplingParams? = nil,
        samples: Int = 1
    ) async throws -> CorrectionResult {
        // Fallback-model retry passes the model explicitly instead of rewriting Settings.
        let resolvedModel = PromptContext.modelOverride ?? model
        CrashLogger.log("performCorrection: start model=\(resolvedModel) type=\(promptType.label) samples=\(samples)")
        let lang = language.isEmpty
            ? LanguageDetector.detect(text: text, fallbackLanguage: resolvedLanguage)
            : language
        let engine = PromptEngine(language: lang, style: await resolveStyle())

        // Self-consistency: only worth it for the deterministic grammar tasks. Fluency/expand
        // are open-ended rewrites where "most conservative" would defeat the purpose.
        let canMultiPass = samples > 1 && (promptType == .grammar || promptType == .grammarAndFluency)

        let corrected: String
        if canMultiPass {
            corrected = try await multiPassCorrect(
                text: text, promptType: promptType, engine: engine, model: resolvedModel,
                url: url, apiKey: apiKey, extraHeaders: extraHeaders,
                sampling: sampling, samples: samples, lang: lang
            )
        } else {
            let rawCorrected = try await performOpenAIRequest(
                body: buildChatBody(text: text, promptType: promptType, engine: engine,
                                    model: resolvedModel, sampling: sampling),
                url: url, apiKey: apiKey, extraHeaders: extraHeaders,
                rejectTruncated: rejectsTruncation(promptType)
            )
            corrected = postProcess(raw: rawCorrected, text: text, promptType: promptType, lang: lang)
        }
        CrashLogger.log("performCorrection: done")
        return CorrectionResult(
            original: text, corrected: corrected,
            modelID: resolvedModel, confidence: Constants.defaultConfidence, promptType: promptType.label
        )
    }

    /// Runs the grammar correction several times with varied seeds and picks the
    /// consensus / most conservative result. Tames small-model noise without a bigger model.
    /// Sequential by design: the local llama-server processes one request at a time, so
    /// parallelism would only contend for the same backend.
    private func multiPassCorrect(
        text: String,
        promptType: PromptType,
        engine: PromptEngine,
        model: String,
        url: URL,
        apiKey: String?,
        extraHeaders: [String: String],
        sampling: SamplingParams?,
        samples: Int,
        lang: String
    ) async throws -> String {
        var votes: [String] = []
        var sawRequest = false
        votes.reserveCapacity(samples)
        for i in 0..<samples {
            try Task.checkCancellation()
            // Pass 0 is the most deterministic; later passes add a little diversity so the
            // vote is meaningful instead of three identical greedy decodes.
            let offset = i == 0 ? 0.0 : 0.15 * Double(i)
            let body = buildChatBody(text: text, promptType: promptType, engine: engine,
                                     model: model, temperatureOffset: offset,
                                     sampling: sampling, seedOverride: i)
            do {
                let raw = try await performOpenAIRequest(body: body, url: url, apiKey: apiKey, extraHeaders: extraHeaders,
                                                         rejectTruncated: rejectsTruncation(promptType))
                sawRequest = true
                let candidate = postProcess(raw: raw, text: text, promptType: promptType, lang: lang)
                let rawEchoedOriginal = raw.trimmingCharacters(in: .whitespacesAndNewlines) == text
                if candidate != text {
                    votes.append(candidate)            // a real, validated correction
                } else if rawEchoedOriginal {
                    votes.append(text)                 // model deliberately said "no change"
                }
                // A strict majority of all planned passes is already decided: the remaining
                // passes cannot change the outcome, so skip them (a full pass costs seconds on
                // an 8B local model).
                if let top = votes.reduce(into: [String: Int](), { $0[$1, default: 0] += 1 }).values.max(),
                   top * 2 > samples {
                    break
                }
                // else: the model DID try to change the text but validateCorrection reverted it
                // (over-correction / hallucination). That is a rejected attempt, NOT a vote for
                // "no change" — dropping it stops a few bad passes from burying one good fix.
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                CrashLogger.log("multiPassCorrect: pass \(i) failed: \(error.localizedDescription)")
            }
        }
        guard sawRequest else {
            // Every request errored — re-issue one so the caller gets a real error, not a silent no-op.
            let body = buildChatBody(text: text, promptType: promptType, engine: engine,
                                     model: model, sampling: sampling)
            let raw = try await performOpenAIRequest(body: body, url: url, apiKey: apiKey, extraHeaders: extraHeaders,
                                                         rejectTruncated: rejectsTruncation(promptType))
            return postProcess(raw: raw, text: text, promptType: promptType, lang: lang)
        }
        // No surviving vote → every pass was a rejected over-correction. Safest is the original.
        guard !votes.isEmpty else { return text }
        return selectConsensus(candidates: votes, original: text)
    }

    /// Picks the best candidate.
    ///
    /// A pass that `validateCorrection` rejected collapses back to the original, so the
    /// candidate set mixes real corrections with "no-op" passes. The original has edit
    /// distance 0, so a naive "most conservative" pick would let a single rejected pass
    /// silently win and produce NO correction. Logic instead:
    ///   1. Strict majority across all passes wins (covers both "agreed fix" and the
    ///      legitimate "text is already correct" case where most passes return the original).
    ///   2. Otherwise, if any pass produced an actual change, pick the most conservative
    ///      CHANGED candidate — never let a lone rejected pass suppress a real fix.
    ///   3. Only fall back to the original when no pass changed anything.
    func selectConsensus(candidates: [String], original: String) -> String {
        guard let first = candidates.first else { return original }
        guard candidates.count > 1 else { return first }

        // 1. Strict majority vote on normalized text.
        var counts: [String: Int] = [:]
        for c in candidates { counts[c, default: 0] += 1 }
        if let (winner, count) = counts.max(by: { $0.value < $1.value }), count * 2 > candidates.count {
            return winner
        }

        // 2. No majority: choose among candidates that actually changed the text — but only when
        //    passes proposing a change outnumber the "no change" votes. A tie (one pass breaks a
        //    correct sentence, one leaves it alone) is no evidence of an error: keep the text.
        let changed = candidates.filter { $0 != original }
        guard !changed.isEmpty else { return original }  // 3. every pass was a no-op
        guard changed.count > candidates.count - changed.count else { return original }

        // Most conservative real correction (fewest edits), ties broken by higher
        // agreement count then shorter length.
        return changed.min { a, b in
            let da = levenshteinDistance(a, original)
            let db = levenshteinDistance(b, original)
            if da != db { return da < db }
            let ca = counts[a] ?? 0, cb = counts[b] ?? 0
            if ca != cb { return ca > cb }
            return a.count < b.count
        } ?? changed[0]
    }

    func validateCorrection(original: String, corrected: String, isFluency: Bool = false, language: String? = nil) -> String {
        CorrectionSanitizer.validate(original: original, corrected: corrected, isFluency: isFluency, language: language)
    }

    private func levenshteinDistance(_ a: String, _ b: String) -> Int {
        CorrectionSanitizer.levenshteinDistance(a, b)
    }

    func chatBody(
        model: String,
        prompt: String,
        systemPrompt: String? = "You are a proofreader. Fix only clear grammatical errors: misspellings, wrong verb forms, wrong agreement. Do NOT add information, do NOT change sentence type, do NOT rephrase, do NOT translate. Output only the corrected text.",
        temperature: Double,
        maxTokens: Int = 1024,
        stream: Bool = false,
        sampling: SamplingParams? = nil
    ) -> ChatRequest {
        var messages: [ChatMessage]
        if let sys = systemPrompt {
            messages = [ChatMessage(role: "system", content: sys), ChatMessage(role: "user", content: prompt)]
        } else {
            messages = [ChatMessage(role: "user", content: prompt)]
        }
        return ChatRequest(model: model, messages: messages, temperature: temperature,
                           max_tokens: maxTokens, stream: stream, sampling: sampling)
    }

    // MARK: - Shared streaming (used by all concrete services)

    func defaultStreamCorrect(
        text: String,
        promptType: PromptType,
        model: String,
        url: URL,
        apiKey: String?,
        extraHeaders: [String: String] = [:],
        sampling: SamplingParams? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let lang = LanguageDetector.detect(text: text, fallbackLanguage: resolvedLanguage)
                    let engine = PromptEngine(language: lang, style: await resolveStyle())
                    // Same system prompt / temperature / context as the one-shot path.
                    let body = buildChatBody(text: text, promptType: promptType, engine: engine,
                                             model: model, sampling: sampling, stream: true)
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

// MARK: - Token budget

enum TokenEstimator {
    /// Conservative tokens-per-text estimate that works for every script: ~3 UTF-8 bytes per
    /// token over-counts Latin text slightly (≈4 chars/token) and gives CJK — 3 bytes per
    /// character, roughly one token each — a full token per character instead of a quarter.
    static let utf8BytesPerToken = 3

    static func estimatedTokens(for text: String) -> Int {
        (text.utf8.count + utf8BytesPerToken - 1) / utf8BytesPerToken
    }
}

// MARK: - Output sanitizing / validation (pure, no I/O)

/// Turns one raw model output into a safe correction. Every structural strip runs only when
/// the ORIGINAL lacks that structure, so the user's own prefixes, quotes and paragraphs survive.
enum CorrectionSanitizer {
    static let maxGrammarLengthRatio = 2
    static let maxFluencyLengthRatio = 6
    /// Grammar output shorter than this fraction of the original is a truncation, not a fix.
    static let minGrammarLengthRatio = 0.6
    /// Below this length a big relative shrink can be legitimate ("the the" → "the").
    static let minLengthForShrinkCheck = 20
    static let maxGrammarWordChange = 0.50
    static let minLengthForLanguageCheck = 5
    static let maxLabelWords = 3
    static let maxRunawayRatio = 10
    static let maxTranslationRatio = 4
    static let minTranslationCap = 200
    /// A first line is a preamble only if almost none of its words come from the original…
    static let maxPreambleOverlap = 0.25
    /// …while the rest of the output still covers most of the original.
    static let minBodyCoverage = 0.5

    private static let quotePairs: [(open: Character, close: Character)] = [
        ("\"", "\""), ("'", "'"), ("“", "”"), ("„", "“"), ("«", "»"), ("「", "」"),
    ]
    private static let labelColons: Set<Character> = [":", "："]
    private static let fence = "```"

    // MARK: Entry points

    static func postProcess(raw: String, original: String, promptType: PromptType, language: String) -> String {
        switch promptType {
        case .grammar, .fluency, .grammarAndFluency, .deSlop:
            return validate(original: original, corrected: raw,
                            isFluency: promptType != .grammar, language: language)
        default:
            let cleaned = stripCodeFence(stripReasoning(trimmed(raw), original: original), original: original)
            guard !cleaned.isEmpty else { return original }
            switch promptType {
            case .expand, .custom:
                // Runaway generation guard (repetition loop, assistant hallucination).
                return cleaned.count <= original.count * maxRunawayRatio ? cleaned : original
            case .translation:
                return cleaned.count <= max(minTranslationCap, original.count * maxTranslationRatio) ? cleaned : original
            default:
                return cleaned
            }
        }
    }

    static func validate(original: String, corrected: String, isFluency: Bool, language: String?) -> String {
        let strips: [(String, String) -> String] = [
            stripReasoning, stripCodeFence, stripLabelPrefix, stripPreamble,
            stripWrappingQuotes, stripTrailingCommentary,
        ]
        let cleaned = strips.reduce(trimmed(corrected)) { text, strip in strip(text, original) }
        guard !cleaned.isEmpty,
              isAcceptable(cleaned, original: original, isFluency: isFluency, language: language)
        else { return original }
        return isFluency ? cleaned : preservePunctuation(original: original, corrected: cleaned)
    }

    // MARK: Structural strips

    /// Removes `<think>…</think>` reasoning. An unterminated block means the answer never came.
    static func stripReasoning(_ text: String, original: String) -> String {
        guard !original.lowercased().contains("<think") else { return text }
        let closed = text.replacingOccurrences(
            of: "(?s)<(think|thinking)>.*?</\\1>", with: "",
            options: [.regularExpression, .caseInsensitive])
        // Chat templates that pre-open <think> leave only the closing tag in the output.
        let afterDangling = closed.range(of: "</think>", options: [.caseInsensitive, .backwards])
            .map { String(closed[$0.upperBound...]) } ?? closed
        let result = trimmed(afterDangling)
        return result.lowercased().hasPrefix("<think") ? "" : result
    }

    static func stripCodeFence(_ text: String, original: String) -> String {
        guard text.hasPrefix(fence), !original.contains(fence) else { return text }
        let body = text.firstIndex(of: "\n").map { String(text[text.index(after: $0)...]) } ?? ""
        let unfenced = trimmed(body)
        return trimmed(unfenced.hasSuffix(fence) ? String(unfenced.dropLast(fence.count)) : unfenced)
    }

    /// "Label: text" with a short label on the first line, split into (label, text).
    static func labelPrefix(of text: String) -> (label: String, remainder: String)? {
        let firstLine = text.prefix(while: { $0 != "\n" })
        guard let colon = firstLine.firstIndex(where: { labelColons.contains($0) }) else { return nil }
        let label = firstLine[..<colon].trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, label.split(whereSeparator: \.isWhitespace).count <= maxLabelWords else { return nil }
        return (label, trimmed(String(text[text.index(after: colon)...])))
    }

    static func stripLabelPrefix(_ text: String, original: String) -> String {
        guard let (label, remainder) = labelPrefix(of: text),
              !remainder.isEmpty, remainder.count >= original.count / 4 else { return text }
        if labelPrefix(of: original) != nil {
            // The user wrote "X: …" (maybe with a typo in X): keep it, unless the model
            // stacked one more label on top ("Corrected: Nota: …").
            return labelPrefix(of: remainder) != nil ? remainder : text
        }
        return original.lowercased().contains(label.lowercased()) ? text : remainder
    }

    /// Drops a colon-less first line ("Here is the corrected text") that shares almost no
    /// words with a single-line original while the rest of the output covers it.
    static func stripPreamble(_ text: String, original: String) -> String {
        let source = trimmed(original)
        guard !source.contains("\n"), let newline = text.firstIndex(of: "\n") else { return text }
        let firstLine = trimmed(String(text[..<newline]))
        let body = trimmed(String(text[newline...]))
        guard !firstLine.isEmpty, !body.isEmpty,
              !source.lowercased().hasPrefix(firstLine.lowercased()) else { return text }
        let sourceWords = Set(wordTokens(source))
        let lineWords = wordTokens(firstLine)
        guard !lineWords.isEmpty else { return text }
        let overlap = Double(lineWords.filter(sourceWords.contains).count) / Double(lineWords.count)
        let coverage = 1 - wordChangeFraction(original: source, corrected: body)
        return overlap <= maxPreambleOverlap && coverage >= minBodyCoverage ? body : text
    }

    static func stripWrappingQuotes(_ text: String, original: String) -> String {
        let source = trimmed(original)
        guard text.count > 2,
              let pair = quotePairs.first(where: { text.first == $0.open && text.last == $0.close }),
              !(source.first == pair.open && source.last == pair.close)
        else { return text }
        return trimmed(String(text.dropFirst().dropLast()))
    }

    /// Commentary after a blank line — only when the original is a single paragraph.
    static func stripTrailingCommentary(_ text: String, original: String) -> String {
        guard !original.contains("\n\n"), let blank = text.range(of: "\n\n") else { return text }
        let first = trimmed(String(text[..<blank.lowerBound]))
        let second = trimmed(String(text[blank.upperBound...]))
        let firstCoversOriginal = Double(first.count) / Double(max(original.count, 1)) >= 0.5
        let secondMuchShorter = second.count < first.count / 2
        return firstCoversOriginal && secondMuchShorter && !first.isEmpty ? first : text
    }

    // MARK: Acceptance checks

    static func isAcceptable(_ text: String, original: String, isFluency: Bool, language: String?) -> Bool {
        // Language drift against the language we KNOW was requested (primary subtag compare,
        // so "zh" == "zh-Hans").
        if let expected = language, !expected.isEmpty, text.count >= minLengthForLanguageCheck {
            let detected = LanguageDetector.detect(text: text, fallbackLanguage: expected)
            guard LanguageDetector.isSameLanguage(detected, expected) else { return false }
        }
        let maxRatio = isFluency ? maxFluencyLengthRatio : maxGrammarLengthRatio
        guard text.count <= original.count * maxRatio else { return false }
        guard !isFluency else { return true }

        if original.count >= minLengthForShrinkCheck,
           Double(text.count) < Double(original.count) * minGrammarLengthRatio {
            return false
        }
        guard wordChangeFraction(original: original, corrected: text) <= maxGrammarWordChange else { return false }
        return !hasHallucinatedWord(original: original, corrected: text, language: language)
    }

    /// Edits up to this share of a word's letters are still a plausible fix of that word.
    private static let maxWordEditRatio = 0.6

    /// Per-word guard (same word count): catches "alcujne"→"Alleggeri" that slips through the
    /// fraction check. Two ways a big edit is still legitimate:
    /// - same lemma = an inflection fix ("avrei"→"avessi", "sarebbe"→"fosse", "went"→"goes");
    /// - the edit touches at most ~60% of the word (short words are skipped entirely).
    private static func hasHallucinatedWord(original: String, corrected: String, language: String?) -> Bool {
        let origWords = wordTokens(original)
        let corrWords = wordTokens(corrected)
        guard origWords.count == corrWords.count else { return false }
        return zip(origWords, corrWords).contains { orig, corr in
            guard orig != corr, orig.count >= 5 else { return false }
            let limit = max(2, Int((Double(orig.count) * maxWordEditRatio).rounded(.up)))
            guard levenshteinDistance(orig, corr) > limit else { return false }
            return !sameLemma(orig, corr, language: language)
        }
    }

    /// True when the system lemmatizer maps both words to the same dictionary form.
    static func sameLemma(_ a: String, _ b: String, language: String?) -> Bool {
        func lemma(_ word: String) -> String? {
            let tagger = NLTagger(tagSchemes: [.lemma])
            tagger.string = word
            if let language, !language.isEmpty {
                tagger.setLanguage(NLLanguage(rawValue: language), range: word.startIndex..<word.endIndex)
            }
            return tagger.tag(at: word.startIndex, unit: .word, scheme: .lemma).0?.rawValue.lowercased()
        }
        guard let la = lemma(a), let lb = lemma(b) else { return false }
        return la == lb
    }

    // MARK: Word-level helpers

    /// Lowercased word tokens. NLTokenizer segments scripts without spaces (Chinese,
    /// Japanese, Thai) into words, so one CJK edit is one changed word, not 100%.
    static func wordTokens(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).map { text[$0].lowercased() }
    }

    /// Fraction of the original's words (multiset) missing from the correction.
    static func wordChangeFraction(original: String, corrected: String) -> Double {
        let origTokens = wordTokens(original)
        guard !origTokens.isEmpty else { return 0 }
        var available = wordTokens(corrected).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        let unmatched = origTokens.filter { token in
            guard let n = available[token], n > 0 else { return true }
            available[token] = n - 1
            return false
        }.count
        return Double(unmatched) / Double(origTokens.count)
    }

    static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a), bChars = Array(b)
        let m = aChars.count, n = bChars.count
        if m == 0 { return n }
        if n == 0 { return m }
        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)
        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                curr[j] = aChars[i-1] == bChars[j-1]
                    ? prev[j-1]
                    : 1 + min(prev[j-1], prev[j], curr[j-1])
            }
            prev = curr
        }
        return prev[n]
    }

    /// Grammar mode must keep the sentence type: restore/replace a changed final . ! ?
    static func preservePunctuation(original: String, corrected: String) -> String {
        let sentenceEnders = CharacterSet(charactersIn: ".!?")
        let allPunct = CharacterSet(charactersIn: ".!?;:")
        let trimmedCorrected = trimmed(corrected)
        guard let origLast = trimmed(original).last,
              origLast != trimmedCorrected.last,
              let origScalar = origLast.unicodeScalars.first,
              sentenceEnders.contains(origScalar)
        else { return corrected }
        if let corrLast = trimmedCorrected.last,
           let corrScalar = corrLast.unicodeScalars.first,
           allPunct.contains(corrScalar) {
            return String(trimmedCorrected.dropLast()) + String(origLast)
        }
        return trimmedCorrected + String(origLast)
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
