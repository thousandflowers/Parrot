import Foundation
import os
import OSLog

private let pendingStateLock = OSAllocatedUnfairLock<(task: Task<Void, Never>?, onCancel: (@Sendable () -> Void)?)>(initialState: (task: nil, onCancel: nil))

struct PreparedCheck: Sendable {
    let text: String
    let bundleID: String?
    let serviceType: ServiceType?
    let promptType: PromptType
    let anchorRect: CGRect?
    let replacementRange: CFRange?
    let capturedPID: pid_t
    let customPrompt: CustomPrompt?
    let resolvedLanguage: String
}

/// Central orchestrator for text checking operations.
/// Check flows (grammar, fluency, translation, etc.) are in TextCheckCoordinator+CheckFlows.swift.
struct TextCheckCoordinator: Sendable {
    static let shared = TextCheckCoordinator()

    func cancelPendingCheck() {
        pendingStateLock.withLock { state in
            state.task?.cancel()
            state.task = nil
            state.onCancel?()
        }
    }

    func openFloatingEditor() async {
        await MainActor.run {
            FloatingEditorController.shared.show()
        }
    }

    // MARK: - Core check execution

    func check(
        type: PromptType,
        pid: pid_t? = nil,
        overrideService: Bool = false,
        show: @escaping @MainActor (CorrectionResult) -> Void
    ) {
        performCheck(frontAppPID: pid) { text, resolved, _, detectedTone, language, bundleID in
            let customResult = await CustomRuleStore.shared.apply(to: text, language: language)
            let customText = customResult.text
            let ruleResult = await RuleBasedEngine.shared.check(customText, language: language)

            let hasCustomFixes = !customResult.fixes.isEmpty
            let hasRuleFixes = ruleResult.hasFixes

            let effectiveType: PromptType
            if type == .grammar {
                let draftScore = DraftDetector.score(text)
                if draftScore.isDraft {
                    effectiveType = .expand
                } else {
                    let isAIChat = await AppDetector.shared.isAIChatApp(bundleID: bundleID)
                    let autoDetect = await MainActor.run { PreferencesStore.shared.aiPromptAutoDetect }
                    if autoDetect && isAIChat {
                        effectiveType = .aiPrompt
                    } else {
                        effectiveType = type
                    }
                }
            } else {
                effectiveType = type
            }

            // --- Span-based pipeline ---
            // Layer 0: NSSpellChecker (main actor, fast, zero deps)
            let nativeSpans: [CorrectionSpan] = await MainActor.run {
                NativeGrammarEngine.check(text, language: language)
            }

            // Layer 1: Rule engine already ran above. Convert to spans.
            let ruleSpans: [CorrectionSpan] = ruleResult.fixes.compactMap { fix in
                guard let range = text.range(of: fix.original) else { return nil }
                return CorrectionSpan(
                    range: NSRange(range, in: text),
                    original: fix.original,
                    replacement: fix.corrected,
                    reason: fix.reason,
                    confidence: 1.0,
                    source: .ruleBased
                )
            }

            // Layer 1b: Harper (EN only)
            var harperSpans: [CorrectionSpan] = []
            let harperAvailable = await HarperEngine.shared.isAvailable
            if harperAvailable && language.hasPrefix("en") {
                if let harperResult = try? await HarperEngine.shared.check(ruleResult.text) {
                    harperSpans = harperResult.fixes.map { fix in
                        CorrectionSpan(
                            range: fix.byteRange,
                            original: fix.original,
                            replacement: fix.corrected,
                            reason: fix.message,
                            confidence: 0.95,
                            source: .ruleBased
                        )
                    }
                }
            }

            // Layer 2: LanguageTool (when installed locally — 500+ rules, 25+ languages)
            var ltSpans: [CorrectionSpan] = []
            if await LanguageToolEngine.shared.isAvailable {
                ltSpans = (try? await LanguageToolEngine.shared.check(text, language: language)) ?? []
            }

            let ruleMerged = SpanMerger.merge(nativeSpans + ruleSpans + harperSpans + ltSpans)

            let serviceType: ServiceType?
            if overrideService {
                serviceType = resolved.serviceType ?? LLMServiceFactory.resolveFluencyServiceType()
            } else {
                serviceType = resolved.serviceType
            }

            var kbContext = await KnowledgeBase.shared.contextForPrompt(text: ruleResult.text)

            // Task 15: Browser URL tone context — detect URL and inject domain hint
            if let bundleID, await AppDetector.shared.isBrowser(bundleID: bundleID) {
                let resolvedPID: pid_t
                if let p = pid { resolvedPID = p } else { resolvedPID = await AccessibilityBridge.shared.lastKnownFrontAppPID() }
                if resolvedPID != 0,
                   let url = await AppDetector.shared.currentBrowserURL(pid: resolvedPID),
                   let toneNote = AppDetector.toneNote(for: url) {
                    kbContext = kbContext.map { $0 + "\n" + toneNote } ?? toneNote
                }
            }

            let finalPromptType: PromptType
            let finalCustomPrompt: CustomPrompt?

            if effectiveType == .expand {
                let contactProfile = await ContactStore.shared.findInText(text)
                let engine = PromptEngine(language: language)
                let expandTemplate = engine.buildExpandPrompt(for: "{{TEXT}}", contactProfile: contactProfile)
                finalPromptType = .custom(name: "Smart Expand", template: expandTemplate)
                finalCustomPrompt = nil
            } else if let kbContext, let cp = resolved.prompt {
                finalPromptType = .custom(name: cp.name, template: cp.template + "\n\n" + kbContext)
                finalCustomPrompt = nil
            } else if let kbContext {
                finalPromptType = effectiveType
                finalCustomPrompt = CustomPrompt(id: UUID(), name: "KB Context", template: kbContext, checkType: .custom)
            } else {
                finalPromptType = effectiveType
                finalCustomPrompt = resolved.prompt
            }

            // Layer 3: LLM always runs (short-circuit removed in Task 1)
            let llmResult = try await RequestQueue.shared.enqueue(
                text: ruleResult.text, type: finalPromptType, priority: .manual,
                overrideServiceType: serviceType, overrideCustomPrompt: finalCustomPrompt,
                language: language
            )

            // Merge: rule spans + LLM diff spans
            let llmSpans = spansFromCorrectionResult(llmResult, original: ruleResult.text)
            let allSpans = SpanMerger.merge(ruleMerged + llmSpans)
            let correctedText = allSpans.isEmpty
                ? llmResult.correctedText
                : SpanApplicator.apply(spans: allSpans, to: text)

            var spanResult = CorrectionResult(
                original: text,
                corrected: correctedText,
                modelID: llmResult.modelID,
                confidence: llmResult.confidence,
                promptType: effectiveType.label,
                detectedTone: detectedTone?.rawValue,
                source: allSpans.isEmpty ? .llm : .hybrid
            )
            spanResult.correctionSpans = allSpans.isEmpty ? nil : allSpans
            return spanResult
        } onSuccess: { result in
            if type.isFluency && !result.hasChanges {
                let noChangeResult = CorrectionResult(
                    original: result.originalText,
                    corrected: result.correctedText,
                    modelID: result.modelID,
                    explanation: result.explanation,
                    confidence: result.confidence,
                    promptType: PromptType.fluency.label,
                    detectedTone: result.detectedTone,
                    source: result.source
                )
                SuggestionPanelController.shared.showFluency(result: noChangeResult)
            } else if let spans = result.correctionSpans, !spans.isEmpty {
                SuggestionPanelController.shared.showSpans(result: result, spans: spans)
            } else {
                show(result)
            }
        }
    }

    // MARK: - Preparation

    func prepareCheck(frontAppPID: pid_t? = nil) async throws -> PreparedCheck {
        let (text, capturedRange) = try await fetchSelectedTextAndRange(frontAppPID: frontAppPID, attempt: 1)
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

        let language = LanguageDetector.detect(
            text: text,
            fallbackLanguage: Locale.current.language.languageCode?.identifier ?? "en"
        )

        let contextPID: pid_t = if let pid = frontAppPID { pid } else { await AccessibilityBridge.shared.lastKnownFrontAppPID() }
        let surroundingText = await AccessibilityBridge.shared.fetchSurroundingText(
            pid: contextPID, selectionRange: capturedRange
        )
        let docContext = ContextAnalyzer.analyze(
            surroundingText: surroundingText.isEmpty ? text : surroundingText,
            appBundleID: bundleID,
            language: language
        )
        async let storeContext: Void = ContextStorage.shared.store(docContext)
        let prefsSnapshot = await MainActor.run { PreferencesStore.shared.snapshot() }
        let resolvedValue = RuleResolver.resolve(
            appBundleID: bundleID,
            customPrompts: prefsSnapshot.customPrompts,
            appRules: prefsSnapshot.appRules
        )
        _ = await storeContext

        return PreparedCheck(
            text: text,
            bundleID: bundleID,
            serviceType: resolvedValue.serviceType,
            promptType: resolvedValue.prompt.map { .custom(name: $0.name, template: $0.template) } ?? .grammar,
            anchorRect: nil,
            replacementRange: capturedRange,
            capturedPID: contextPID,
            customPrompt: resolvedValue.prompt,
            resolvedLanguage: language
        )
    }

    // MARK: - Task execution

    func performCheck(
        frontAppPID: pid_t? = nil,
        action: @escaping @Sendable (String, (serviceType: ServiceType?, prompt: CustomPrompt?), CFRange?, DetectedTone?, String, String?) async throws -> CorrectionResult,
        onSuccess: @escaping @MainActor (CorrectionResult) -> Void
    ) {
        runTask {
            CrashLogger.log("performCheck: prepareCheck start")
            let prepared = try await self.prepareCheck(frontAppPID: frontAppPID)
            CrashLogger.log("performCheck: prepareCheck done, text=\(prepared.text.prefix(30))")
            await MainActor.run { SuggestionPanelController.shared.showLoading() }

            let replacementRange: CFRange = prepared.replacementRange ?? CFRange(location: 0, length: 0)
            let detectedTone = await ToneDetector.shared.detect(text: prepared.text, language: prepared.resolvedLanguage)
            CrashLogger.log("performCheck: running action, promptType=\(prepared.promptType.label)")

            let resolved = (serviceType: prepared.serviceType, prompt: prepared.customPrompt)
            let rawResult = try await action(prepared.text, resolved, replacementRange, detectedTone, prepared.resolvedLanguage, prepared.bundleID)
            CrashLogger.log("performCheck: action done")

            let anchorRange: CFRange = await AccessibilityBridge.shared.lastSelectedRange
            let anchorRect: CGRect? = anchorRange.length > 0
                ? await AccessibilityBridge.shared.boundsForRange(anchorRange, pid: prepared.capturedPID)
                : nil

            var mutableResult = CorrectionResult(
                original: rawResult.originalText,
                corrected: rawResult.correctedText,
                modelID: rawResult.modelID,
                explanation: rawResult.explanation,
                confidence: rawResult.confidence,
                customInstruction: rawResult.customInstruction,
                promptType: rawResult.promptType,
                detectedTone: rawResult.detectedTone ?? detectedTone.rawValue,
                source: rawResult.source)
            mutableResult.replacementRange = replacementRange
            mutableResult.anchorRect = anchorRect
            let finalResult = mutableResult

            try Task.checkCancellation()
            await MainActor.run { onSuccess(finalResult) }

            let textOffset = self.replaceOffset(for: replacementRange)
            await self.showInlineAnnotations(result: finalResult, textOffset: textOffset, pid: prepared.capturedPID)
        }
    }

    func runTask(body: @escaping @Sendable () async throws -> Void) {
        pendingStateLock.withLock { state in
            state.task?.cancel()
            state.task = Task {
                await MainActor.run { MenuBarBirdAnimator.shared.setState(.analyzing) }
                do {
                    try Task.checkCancellation()
                    try await body()
                } catch is CancellationError {
                    await MainActor.run {
                        MenuBarBirdAnimator.shared.setState(.idle)
                        if SuggestionPanelController.shared.isLoading {
                            SuggestionPanelController.shared.close()
                        }
                    }
                } catch let error as CorrectionError {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        MenuBarBirdAnimator.shared.setState(.idle)
                        SuggestionPanelController.shared.showError(error)
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        MenuBarBirdAnimator.shared.setState(.idle)
                        SuggestionPanelController.shared.showError(.outputParsingFailed(raw: error.localizedDescription))
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    func showInlineAnnotations(result: CorrectionResult, textOffset: Int, pid: pid_t) async {
        let annots = result.toAnnotations(baseOffset: textOffset)
        if !annots.isEmpty {
            await MainActor.run { InlineHighlightController.shared.show(annots, pid: pid) }
        }
    }

    func replaceOffset(for replacementRange: CFRange) -> Int {
        replacementRange.length > 0 ? replacementRange.location : 0
    }

    private func spansFromCorrectionResult(_ result: CorrectionResult, original: String) -> [CorrectionSpan] {
        guard result.hasChanges, let ops = result.diffOperations else { return [] }
        return ops.compactMap { op in
            switch op.type {
            case .insert:
                guard let replacement = op.replacement, !replacement.isEmpty else { return nil }
                return CorrectionSpan(
                    range: NSRange(location: op.offset, length: 0),
                    original: "",
                    replacement: replacement,
                    reason: "AI correction",
                    confidence: result.confidence ?? 0.85,
                    source: .llm
                )
            case .delete:
                let nsRange = NSRange(location: op.offset, length: op.length)
                guard let swiftRange = Range(nsRange, in: original) else { return nil }
                let orig = String(original[swiftRange])
                return CorrectionSpan(
                    range: nsRange,
                    original: orig,
                    replacement: op.replacement ?? "",
                    reason: "AI correction",
                    confidence: result.confidence ?? 0.85,
                    source: .llm
                )
            }
        }
    }

    private func fetchSelectedTextAndRange(frontAppPID: pid_t?, attempt: Int) async throws -> (String, CFRange) {
        let maxAttempts = 2
        do {
            if let pid = frontAppPID {
                let bid = await AppDetector.shared.frontAppBundleID(forPID: pid)
                if let b = bid, await ElectronFallbackHandler.shared.isElectronApp(bundleID: b) {
                    let text = try await ElectronFallbackHandler.shared.extractViaClipboard(pid: pid)
                    return (text, CFRange(location: 0, length: 0))
                }
                let text = try await AccessibilityBridge.shared.fetchSelectedText(fromPID: pid)
                let range = await AccessibilityBridge.shared.lastSelectedRange
                return (text, range)
            }
            let text = try await AccessibilityBridge.shared.fetchSelectedText()
            let range = await AccessibilityBridge.shared.lastSelectedRange
            return (text, range)
        } catch CorrectionError.noTextSelected {
            guard attempt < maxAttempts else {
                let pid: pid_t
                if let p = frontAppPID { pid = p } else { pid = await AccessibilityBridge.shared.lastKnownFrontAppPID() }
                return try await AccessibilityBridge.shared.fetchTextOrLineAtCursor(fromPID: pid)
            }
            try await Task.sleep(nanoseconds: 300_000_000)
            return try await fetchSelectedTextAndRange(frontAppPID: frontAppPID, attempt: attempt + 1)
        } catch CorrectionError.textExtractionFailed where frontAppPID == nil {
            // System-wide AX focus query can fail on macOS 26+ — fall back to last known PID
            let pid = await AccessibilityBridge.shared.lastKnownFrontAppPID()
            guard pid != 0 else { throw CorrectionError.textExtractionFailed(appName: "unknown") }
            let bid = await AppDetector.shared.frontAppBundleID(forPID: pid)
            if let b = bid, await ElectronFallbackHandler.shared.isElectronApp(bundleID: b) {
                let text = try await ElectronFallbackHandler.shared.extractViaClipboard(pid: pid)
                return (text, CFRange(location: 0, length: 0))
            }
            let text = try await AccessibilityBridge.shared.fetchSelectedText(fromPID: pid)
            let range = await AccessibilityBridge.shared.lastSelectedRange
            return (text, range)
        }
    }
}
