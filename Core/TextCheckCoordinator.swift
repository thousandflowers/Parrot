import Foundation

private final class PendingState: @unchecked Sendable {
    let lock = NSLock()
    var task: Task<Void, Never>?
    var onCancel: (@Sendable () -> Void)?
}

private struct PreparedCheck: Sendable {
    let text: String
    let bundleID: String?
    let serviceType: ServiceType
    let promptType: PromptType
    let anchorRect: CGRect?
    let replacementRange: CFRange?
    let capturedPID: pid_t
    let customPrompt: CustomPrompt?
}

struct TextCheckCoordinator: Sendable {
    static let shared = TextCheckCoordinator()

    private let pendingState = PendingState()

    func checkSelectedText() {
        check(type: .grammar, show: { SuggestionPanelController.shared.show(result: $0) })
    }

    func checkSelectedText(fromPID pid: pid_t) {
        check(type: .grammar, pid: pid, show: { SuggestionPanelController.shared.show(result: $0) })
    }

    func checkFluency() {
        check(type: .fluency, overrideService: true, show: { SuggestionPanelController.shared.showFluency(result: $0) })
    }

    func checkFluency(fromPID pid: pid_t) {
        check(type: .fluency, pid: pid, overrideService: true, show: { SuggestionPanelController.shared.showFluency(result: $0) })
    }

    private func check(
        type: PromptType,
        pid: pid_t? = nil,
        overrideService: Bool = false,
        show: @escaping @MainActor (CorrectionResult) -> Void
    ) {
        let checkType: SuggestionPanelController.RetryCheckType
        if case .fluency = type { checkType = .fluency(pid) } else { checkType = .grammar(pid) }
        performCheck(frontAppPID: pid, checkType: checkType) { text, resolved, _, detectedTone in
            let storedLanguage = await MainActor.run { PreferencesStore.shared.language }
            let language = storedLanguage == "auto"
                ? LanguageDetector.detect(
                    text: text,
                    fallbackLanguage: Locale.current.language.languageCode?.identifier ?? "en"
                  )
                : storedLanguage

            let customResult = await CustomRuleStore.shared.apply(to: text, language: language)
            let customText = customResult.text

            let ruleResult = await RuleBasedEngine.shared.check(customText, language: language)

            let hasCustomFixes = !customResult.fixes.isEmpty
            let hasRuleFixes = ruleResult.hasFixes

            if (hasCustomFixes || hasRuleFixes) && language != "en" {
                return CorrectionResult(
                    original: text,
                    corrected: ruleResult.text,
                    modelID: hasCustomFixes ? "custom+rules" : "rule_based",
                    confidence: 1.0,
                    promptType: type.label,
                    detectedTone: detectedTone?.rawValue,
                    source: .ruleBased
                )
            }

            let baseText = ruleResult.text
            let harperAvailable = await HarperEngine.shared.isAvailable

            if harperAvailable && language.hasPrefix("en") {
                do {
                    let harperResult = try await HarperEngine.shared.check(baseText)
                    if harperResult.hasFixes {
                        return CorrectionResult(
                            original: text,
                            corrected: harperResult.text,
                            modelID: "harper",
                            confidence: 1.0,
                            promptType: type.label,
                            detectedTone: detectedTone?.rawValue,
                            source: .ruleBased
                        )
                    }
                } catch {
                    // Fall through to LLM
                }
            }

            let serviceType: ServiceType?
            if overrideService {
                serviceType = resolved.serviceType ?? LLMServiceFactory.resolveFluencyServiceType()
            } else {
                serviceType = resolved.serviceType
            }
            return try await RequestQueue.shared.enqueue(
                text: baseText, type: type, priority: .manual,
                overrideServiceType: serviceType, overrideCustomPrompt: resolved.prompt
            )
        } onSuccess: { result in
            show(result)
        }
    }

    func cancelPendingCheck() {
        pendingState.lock.withLock {
            pendingState.task?.cancel()
            pendingState.task = nil
            pendingState.onCancel?()
        }
    }

    func openFloatingEditor() async {
        await MainActor.run {
            FloatingEditorController.shared.show()
        }
    }

    func checkStreaming() {
        runTask {
            let prepared = try await prepareCheck()

            let service = LLMServiceFactory.make(with: prepared.serviceType)
            await MainActor.run { SuggestionPanelController.shared.showLoading(checkType: .grammar(prepared.capturedPID)) }
            var accumulated = ""
            let stream = service.streamCorrect(text: prepared.text, promptType: prepared.promptType)
            for try await chunk in stream {
                accumulated = chunk
                let snapshot = accumulated
                await MainActor.run {
                    SuggestionPanelController.shared.showStreaming(original: prepared.text, accumulated: snapshot)
                }
            }
            try Task.checkCancellation()
            let finalText = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = CorrectionResult(original: prepared.text, corrected: finalText, modelID: "streaming", confidence: 0.9, promptType: prepared.promptType.label)
            await MainActor.run { SuggestionPanelController.shared.show(result: result) }

            await showInlineAnnotations(result: result, textOffset: prepared.replacementRange?.location ?? 0, pid: prepared.capturedPID)
        }
    }

    // MARK: - Translation

    func translateSelectedText(to language: String) {
        performCheck(frontAppPID: nil, checkType: .translation(nil, language: language)) { text, resolved, _, _ in
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
        Task { @MainActor in
            translateSelectedText(to: PreferencesStore.shared.translationLanguage)
        }
    }

    // MARK: - Replace

    func checkAndReplace() {
        performCheck(frontAppPID: nil, checkType: .grammar(nil)) { text, resolved, _, _ in
            return try await RequestQueue.shared.enqueue(
                text: text, type: .grammar, priority: .manual,
                overrideServiceType: resolved.serviceType,
                overrideCustomPrompt: resolved.prompt
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
        performCheck(frontAppPID: nil, checkType: .grammar(nil)) { text, resolved, _, _ in
            return try await RequestQueue.shared.enqueue(
                text: text, type: .grammar, priority: .manual,
                overrideServiceType: resolved.serviceType,
                overrideCustomPrompt: resolved.prompt
            )
        } onSuccess: { result in
            guard result.hasChanges else {
                Task { @MainActor in
                    DirectApplyToast.show(message: "Nessuna correzione necessaria")
                }
                return
            }
            Task {
                do {
                    let original = result.originalText
                    let pid = AccessibilityBridge.lastKnownFrontAppPID
                    try await AccessibilityBridge.shared.replaceSelectedText(with: result.correctedText)
                    await MainActor.run {
                        DirectApplyToast.showUndo(
                            message: "Correzione applicata",
                            original: original,
                            corrected: result.correctedText,
                            pid: pid
                        )
                    }
                } catch {
                    await MainActor.run {
                        DirectApplyToast.show(message: "Errore: \(error.localizedDescription)")
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
                    let fluencyResult = try await RequestQueue.shared.enqueue(
                        text: corrected,
                        type: .fluency,
                        priority: .manual,
                        overrideServiceType: serviceType
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
                    await MainActor.run {
                        SuggestionPanelController.shared.lastCheckType = .grammarThenFluency(nil)
                        SuggestionPanelController.shared.show(result: combined)
                    }
                } catch {
                    await MainActor.run { SuggestionPanelController.shared.show(result: grammarResult) }
                }
            }
        }
    }

    func checkLLMOnly(original: String) {
        performCheck(frontAppPID: nil, checkType: .grammar(nil)) { text, resolved, _, detectedTone in
            let serviceType: ServiceType? = resolved.serviceType ?? LLMServiceFactory.resolveDefaultServiceType()
            return try await RequestQueue.shared.enqueue(
                text: text, type: .grammar, priority: .manual,
                overrideServiceType: serviceType, overrideCustomPrompt: resolved.prompt
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

    // MARK: - Writing Coach

    func checkCoach() {
        performCheck(frontAppPID: nil, checkType: .grammar(nil)) { text, _, _, detectedTone in
            let serviceType = LLMServiceFactory.resolveDefaultServiceType()
            return try await RequestQueue.shared.enqueue(
                text: text, type: .coach, priority: .manual,
                overrideServiceType: serviceType
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

    // MARK: - Shared prepareCheck

    private func prepareCheck(frontAppPID: pid_t? = nil) async throws -> PreparedCheck {
        let text = try await fetchSelectedText(frontAppPID: frontAppPID, attempt: 1)
        let bundleID: String?
        if let pid = frontAppPID {
            bundleID = await AppDetector.shared.frontAppBundleID(forPID: pid)
        } else {
            bundleID = await AccessibilityBridge.shared.frontAppBundleID()
        }
        try Task.checkCancellation()
        guard !text.isEmpty else { throw CorrectionError.noTextSelected }

        if let id = bundleID {
            let excluded = await MainActor.run { PreferencesStore.shared.isExcluded(bundleID: id) }
            guard !excluded else { throw CancellationError() }
        }

        let language = await MainActor.run { PreferencesStore.shared.language }
        let _ = await ToneDetector.shared.detect(text: text, language: language)

        let resolved = await MainActor.run {
            RuleResolver.resolve(
                appBundleID: bundleID,
                customPrompts: PreferencesStore.shared.customPrompts,
                appRules: PreferencesStore.shared.appRules
            )
        }

        let capturedPID: pid_t = frontAppPID ?? AccessibilityBridge.lastKnownFrontAppPID
        let replacementRange = CFRange(location: 0, length: 0)
        let anchorRect: CGRect? = nil

        return PreparedCheck(
            text: text,
            bundleID: bundleID,
            serviceType: resolved.serviceType ?? LLMServiceFactory.resolveDefaultServiceType(),
            promptType: resolved.prompt.map { .custom(name: $0.name, template: $0.template) } ?? .grammar,
            anchorRect: anchorRect,
            replacementRange: replacementRange,
            capturedPID: capturedPID,
            customPrompt: resolved.prompt
        )
    }

    // MARK: - performCheck (task wrapper)

    private func performCheck(
        frontAppPID: pid_t? = nil,
        checkType: SuggestionPanelController.RetryCheckType = .grammar(nil),
        action: @escaping @Sendable (String, (serviceType: ServiceType?, prompt: CustomPrompt?), CFRange?, DetectedTone?) async throws -> CorrectionResult,
        onSuccess: @escaping @MainActor (CorrectionResult) -> Void
    ) {
        runTask {
            let prepared = try await self.prepareCheck(frontAppPID: frontAppPID)
            await MainActor.run { SuggestionPanelController.shared.showLoading(checkType: checkType) }

            let replacementRange: CFRange = prepared.replacementRange ?? CFRange(location: 0, length: 0)
            let storedLangForTone = await MainActor.run { PreferencesStore.shared.language }
            let language = storedLangForTone == "auto"
                ? LanguageDetector.detect(
                    text: prepared.text,
                    fallbackLanguage: Locale.current.language.languageCode?.identifier ?? "en"
                  )
                : storedLangForTone
            let detectedTone = await ToneDetector.shared.detect(text: prepared.text, language: language)

            let resolved = (serviceType: prepared.customPrompt.map { _ in prepared.serviceType }, prompt: prepared.customPrompt)
            let rawResult = try await action(prepared.text, resolved, replacementRange, detectedTone)

            let anchorRange: CFRange = await AccessibilityBridge.shared.lastSelectedRange
            let anchorRect: CGRect? = anchorRange.length > 0
                ? await AccessibilityBridge.shared.boundsForRange(anchorRange, pid: prepared.capturedPID)
                : nil

            let finalResult: CorrectionResult = {
                var r = CorrectionResult(
                    original: rawResult.originalText,
                    corrected: rawResult.correctedText,
                    modelID: rawResult.modelID,
                    explanation: rawResult.explanation,
                    confidence: rawResult.confidence,
                    customInstruction: rawResult.customInstruction,
                    promptType: rawResult.promptType,
                    detectedTone: detectedTone.rawValue)
                r.replacementRange = replacementRange
                r.anchorRect = anchorRect
                return r
            }()

            try Task.checkCancellation()
            await MainActor.run { onSuccess(finalResult) }

            let textOffset = replaceOffset(for: replacementRange)
            await showInlineAnnotations(result: finalResult, textOffset: textOffset, pid: prepared.capturedPID)
        }
    }

    // MARK: - runTask helper

    private func runTask(body: @escaping @Sendable () async throws -> Void) {
        pendingState.lock.withLock {
            pendingState.task?.cancel()
            pendingState.task = Task {
                do {
                    try Task.checkCancellation()
                    try await body()
                } catch is CancellationError {
                } catch let error as CorrectionError {
                    guard !Task.isCancelled else { return }
                    await MainActor.run { SuggestionPanelController.shared.showError(error) }
                } catch {
                    guard !Task.isCancelled else { return }
                    await MainActor.run { SuggestionPanelController.shared.showError(.outputParsingFailed(raw: error.localizedDescription)) }
                }
            }
        }
    }

    // MARK: - Inline annotations

    private func showInlineAnnotations(result: CorrectionResult, textOffset: Int, pid: pid_t) async {
        let annots = result.toAnnotations(baseOffset: textOffset)
        if !annots.isEmpty {
            await MainActor.run { InlineHighlightController.shared.show(annots, pid: pid) }
        }
    }

    private func replaceOffset(for replacementRange: CFRange) -> Int {
        replacementRange.length > 0 ? replacementRange.location : 0
    }

    // MARK: - fetchSelectedText (retry)

    private func fetchSelectedText(frontAppPID: pid_t?, attempt: Int) async throws -> String {
        let maxAttempts = 2
        do {
            if let pid = frontAppPID {
                let bid = await AppDetector.shared.frontAppBundleID(forPID: pid)
                if let b = bid, await ElectronFallbackHandler.shared.isElectronApp(bundleID: b) {
                    return try await ElectronFallbackHandler.shared.extractViaClipboard(pid: pid)
                }
                return try await AccessibilityBridge.shared.fetchSelectedText(fromPID: pid)
            }
            return try await AccessibilityBridge.shared.fetchSelectedText()
        } catch CorrectionError.noTextSelected {
            guard attempt < maxAttempts else {
                let pid = frontAppPID ?? AccessibilityBridge.lastKnownFrontAppPID
                let (fallbackText, _) = try await AccessibilityBridge.shared.fetchTextOrLineAtCursor(fromPID: pid)
                return fallbackText
            }
            try await Task.sleep(nanoseconds: 300_000_000)
            return try await fetchSelectedText(frontAppPID: frontAppPID, attempt: attempt + 1)
        }
    }
}
