import Foundation

// MARK: - Check Flows Extension
// All public check methods extracted from TextCheckCoordinator for readability.
// The coordinator's core infrastructure (prepareCheck, performCheck, runTask)
// remains in TextCheckCoordinator.swift.

extension TextCheckCoordinator {

    // MARK: - Grammar

    func checkSelectedText() {
        check(type: .grammar) { SuggestionPanelController.shared.show(result: $0) }
    }

    func checkSelectedText(fromPID pid: pid_t) {
        check(type: .grammar, pid: pid) { SuggestionPanelController.shared.show(result: $0) }
    }

    // MARK: - Fluency

    func checkFluency() {
        check(type: .fluency, overrideService: true) { SuggestionPanelController.shared.showFluency(result: $0) }
    }

    func checkFluency(fromPID pid: pid_t) {
        check(type: .fluency, pid: pid, overrideService: true) { SuggestionPanelController.shared.showFluency(result: $0) }
    }

    // MARK: - Streaming

    func checkStreaming() {
        runTask {
            let prepared = try await prepareCheck()
            let serviceType = prepared.serviceType ?? LLMServiceFactory.resolveDefaultServiceType()
            let service = LLMServiceFactory.make(with: serviceType)
            let modelID = LLMServiceFactory.resolveModelID(for: serviceType)
            let detectedTone = await ToneDetector.shared.detect(
                text: prepared.text, language: prepared.resolvedLanguage
            )

            // Cache lookup before streaming
            if let cached = await CorrectionCache.shared.get(
                text: prepared.text,
                promptType: prepared.promptType.label,
                modelID: modelID,
                language: prepared.resolvedLanguage
            ) {
                await MainActor.run { SuggestionPanelController.shared.show(result: cached) }
                await showInlineAnnotations(
                    result: cached,
                    textOffset: prepared.replacementRange?.location ?? 0,
                    pid: prepared.capturedPID
                )
                return
            }

            var accumulated = ""
            let stream = service.streamCorrect(text: prepared.text, promptType: prepared.promptType)
            for try await chunk in stream {
                accumulated = chunk
                let snapshot = chunk
                await MainActor.run {
                    SuggestionPanelController.shared.showOrUpdateStreaming(
                        original: prepared.text, current: snapshot
                    )
                }
            }
            try Task.checkCancellation()
            let finalText = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
            var result = CorrectionResult(
                original: prepared.text,
                corrected: finalText,
                modelID: modelID,
                confidence: 0.9,
                promptType: prepared.promptType.label,
                detectedTone: detectedTone.rawValue
            )
            result.replacementRange = prepared.replacementRange
            let finalResult = result

            // Store in cache
            await CorrectionCache.shared.set(
                finalResult,
                text: prepared.text,
                promptType: prepared.promptType.label,
                modelID: modelID,
                language: prepared.resolvedLanguage
            )

            await MainActor.run { SuggestionPanelController.shared.show(result: finalResult) }
            await showInlineAnnotations(
                result: finalResult,
                textOffset: prepared.replacementRange?.location ?? 0,
                pid: prepared.capturedPID
            )
        }
    }

    // MARK: - Translation

    func translateSelectedText(to language: String) {
        performCheck(frontAppPID: nil) { text, _, _, _, _, _ in
            return try await RequestQueue.shared.enqueue(
                text: text,
                type: .translation(targetLanguage: language),
                priority: .manual
            )
        } onSuccess: { result in
            SuggestionPanelController.shared.show(result: result)
        }
    }

    func checkTranslation() {
        runTask {
            let prepared = try await prepareCheck()
            let selRange = prepared.replacementRange ?? CFRange(location: 0, length: 0)
            let targetLanguage = await TranslationTargetDetector.detect(
                sourceLanguage: prepared.resolvedLanguage,
                pid: prepared.capturedPID,
                selectionRange: selRange
            )
            var result = try await RequestQueue.shared.enqueue(
                text: prepared.text,
                type: .translation(targetLanguage: targetLanguage),
                priority: .manual
            )
            result.replacementRange = selRange
            let finalResult = result
            await MainActor.run { SuggestionPanelController.shared.show(result: finalResult) }
        }
    }

    // MARK: - Replace

    func checkAndReplace() {
        performCheck(frontAppPID: nil) { text, resolved, _, _, language, _ in
            return try await RequestQueue.shared.enqueue(
                text: text, type: .grammar, priority: .manual,
                overrideServiceType: resolved.serviceType,
                overrideCustomPrompt: resolved.prompt,
                language: language
            )
        } onSuccess: { result in
            guard result.hasChanges else { return }
            Task {
                do {
                    try await AccessibilityBridge.shared.replaceSelectedText(with: result.correctedText)
                } catch {
                    await MainActor.run {
                        SuggestionPanelController.shared.showError(error as? CorrectionError ?? .textExtractionFailed(appName: "unknown"))
                    }
                }
            }
        }
    }

    // MARK: - Apply Direct (no panel)

    func checkAndApplyDirect() {
        performCheck(frontAppPID: nil) { text, resolved, _, _, language, _ in
            return try await RequestQueue.shared.enqueue(
                text: text, type: .grammar, priority: .manual,
                overrideServiceType: resolved.serviceType,
                overrideCustomPrompt: resolved.prompt,
                language: language
            )
        } onSuccess: { result in
            guard result.hasChanges else {
                Task { @MainActor in
                    DirectApplyToast.showSuccess()
                }
                return
            }
            Task {
                do {
                    let original = result.originalText
                    let pid = await AccessibilityBridge.shared.lastKnownFrontAppPID()
                    try await AccessibilityBridge.shared.replaceSelectedText(with: result.correctedText)
                    await MainActor.run {
                        DirectApplyToast.showUndo(
                            message: "Correction applied",
                            original: original,
                            corrected: result.correctedText,
                            pid: pid
                        )
                    }
                } catch {
                    await MainActor.run {
                        DirectApplyToast.show(message: "Error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: - Grammar then Fluency

    func checkGrammarThenFluency() {
        check(type: .grammar) { grammarResult in
            guard grammarResult.hasChanges else {
                self.checkFluency()
                return
            }
            Task {
                do {
                    let corrected = grammarResult.correctedText
                    let serviceType = LLMServiceFactory.resolveFluencyServiceType()
                    let lang = LanguageDetector.detect(text: grammarResult.originalText, fallbackLanguage: "en")
                    let fluencyResult = try await RequestQueue.shared.enqueue(
                        text: corrected,
                        type: .fluency,
                        priority: .manual,
                        overrideServiceType: serviceType,
                        language: lang
                    )
                    let combined = CorrectionResult(
                        original: grammarResult.originalText,
                        corrected: fluencyResult.correctedText,
                        modelID: "grammar+fluency",
                        explanation: fluencyResult.explanation,
                        confidence: min(grammarResult.confidence ?? 0.9, fluencyResult.confidence ?? 0.9),
                        promptType: PromptType.fluency.label,
                        detectedTone: grammarResult.detectedTone,
                        source: .hybrid
                    )
                    await MainActor.run { SuggestionPanelController.shared.show(result: combined) }
                } catch {
                    await MainActor.run { SuggestionPanelController.shared.show(result: grammarResult) }
                }
            }
        }
    }

    // MARK: - LLM Only

    func checkLLMOnly(original: String) {
        performCheck(frontAppPID: nil) { text, resolved, _, _, language, _ in
            let serviceType: ServiceType? = resolved.serviceType ?? LLMServiceFactory.resolveDefaultServiceType()
            return try await RequestQueue.shared.enqueue(
                text: text, type: .grammar, priority: .manual,
                overrideServiceType: serviceType, overrideCustomPrompt: resolved.prompt,
                language: language
            )
        } onSuccess: { result in
            let llmResult = CorrectionResult(
                original: result.originalText,
                corrected: result.correctedText,
                modelID: result.modelID,
                explanation: result.explanation,
                confidence: result.confidence,
                promptType: result.promptType,
                detectedTone: result.detectedTone,
                source: .llm
            )
            SuggestionPanelController.shared.show(result: llmResult)
        }
    }

    // MARK: - Direct text correction (for deep links / PopClip)

    func correctText(_ text: String, mode: PromptType) {
        let language = LanguageDetector.detect(text: text, fallbackLanguage: "en")
        let serviceType = LLMServiceFactory.resolveDefaultServiceType()
        let service = LLMServiceFactory.make(with: serviceType)
        let modelID = LLMServiceFactory.resolveModelID(for: serviceType)

        Task {
            var accumulated = ""
            let stream = service.streamCorrect(text: text, promptType: mode)
            for try await chunk in stream {
                accumulated = chunk
                let snapshot = chunk
                await MainActor.run {
                    SuggestionPanelController.shared.showOrUpdateStreaming(
                        original: text, current: snapshot
                    )
                }
            }
            try Task.checkCancellation()
            let finalText = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = CorrectionResult(
                original: text,
                corrected: finalText,
                modelID: modelID,
                confidence: 0.9,
                promptType: mode.label,
                detectedTone: ""
            )

            await CorrectionCache.shared.set(
                result,
                text: text,
                promptType: mode.label,
                modelID: modelID,
                language: language
            )

            await MainActor.run { SuggestionPanelController.shared.show(result: result) }
        }
    }

    // MARK: - Writing Coach

    func checkCoach() {
        performCheck(frontAppPID: nil) { text, _, _, _, language, _ in
            return try await RequestQueue.shared.enqueue(
                text: text, type: .coach, priority: .manual,
                overrideServiceType: LLMServiceFactory.resolveDefaultServiceType(),
                language: language
            )
        } onSuccess: { result in
            let coachResult = CorrectionResult(
                original: result.originalText,
                corrected: result.correctedText,
                modelID: result.modelID,
                explanation: result.explanation,
                confidence: result.confidence,
                promptType: "coach",
                detectedTone: result.detectedTone,
                source: .llm
            )
            SuggestionPanelController.shared.show(result: coachResult)
        }
    }

    // MARK: - De-Slop

    func checkDeSlop() {
        performCheck(frontAppPID: nil) { text, _, _, _, language, _ in
            return try await RequestQueue.shared.enqueue(
                text: text, type: .deSlop, priority: .manual,
                overrideServiceType: LLMServiceFactory.resolveDefaultServiceType(),
                language: language
            )
        } onSuccess: { result in
            SuggestionPanelController.shared.show(result: result)
        }
    }

    // MARK: - AI Prompt Mode

    func checkAIPrompt() {
        performCheck(frontAppPID: nil) { text, _, _, _, language, _ in
            return try await RequestQueue.shared.enqueue(
                text: text, type: .aiPrompt, priority: .manual,
                overrideServiceType: LLMServiceFactory.resolveDefaultServiceType(),
                language: language
            )
        } onSuccess: { result in
            SuggestionPanelController.shared.show(result: result)
        }
    }

    // MARK: - Plagiarism

    func checkPlagiarism() {
        performCheck(frontAppPID: nil) { text, _, _, _, _, _ in
            let methods: Set<PlagiarismMethod> = [.webSearch, .knowledgeBase, .llmAnalysis]
            let result = await PlagiarismDetector.shared.detect(text: text, methods: methods)
            let report = formatPlagiarismReport(result)
            return CorrectionResult(
                original: text,
                corrected: text,
                modelID: "plagiarism-detector",
                explanation: report,
                confidence: 1.0 - result.overallScore,
                promptType: "plagiarism",
                detectedTone: nil,
                source: .ruleBased
            )
        } onSuccess: { result in
            SuggestionPanelController.shared.show(result: result)
        }
    }

    // MARK: - Helpers

    private func formatPlagiarismReport(_ result: PlagiarismResult) -> String {
        let score = Int(result.overallScore * 100)
        var lines: [String] = []
        lines.append("Plagiarism Analysis")
        lines.append("Overall Score: \(score)%")
        lines.append("")
        if result.findings.isEmpty {
            lines.append("No potential plagiarism detected.")
        } else {
            lines.append("Findings:")
            for finding in result.findings {
                lines.append("  • Source: \(finding.source.rawValue)")
                lines.append("    Match: \(Int(finding.confidence * 100))% similarity")
                if let url = finding.url { lines.append("    URL: \(url)") }
                let snippet = String(finding.matchText.prefix(150))
                lines.append("    Text: \"\(snippet)\"")
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }
}
