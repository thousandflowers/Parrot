import Foundation

private final class PendingState: @unchecked Sendable {
    let lock = NSLock()
    var task: Task<Void, Never>?
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
        guard UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.isFluencyCheckingEnabled) else { return }
        check(type: .fluency, overrideService: true, show: { SuggestionPanelController.shared.showFluency(result: $0) })
    }

    func checkFluency(fromPID pid: pid_t) {
        guard UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.isFluencyCheckingEnabled) else { return }
        check(type: .fluency, pid: pid, overrideService: true, show: { SuggestionPanelController.shared.showFluency(result: $0) })
    }

    private func check(
        type: PromptType,
        pid: pid_t? = nil,
        overrideService: Bool = false,
        show: @escaping @MainActor (CorrectionResult) -> Void
    ) {
        performCheck(frontAppPID: pid) { text, resolved, _, _ in
            let serviceType: ServiceType?
            if overrideService {
                serviceType = resolved.serviceType ?? LLMServiceFactory.resolveFluencyServiceType()
            } else {
                serviceType = resolved.serviceType
            }
            return try await RequestQueue.shared.enqueue(
                text: text, type: type, priority: .manual,
                overrideServiceType: serviceType, overrideCustomPrompt: resolved.prompt
            )
        } onSuccess: { result in
            show(result)
        }
    }

    func openFloatingEditor() async {
        await MainActor.run {
            FloatingEditorController.shared.show()
        }
    }

    private func performCheck(
        frontAppPID: pid_t? = nil,
        action: @escaping @Sendable (String, (serviceType: ServiceType?, prompt: CustomPrompt?), CFRange?, DetectedTone?) async throws -> CorrectionResult,
        onSuccess: @escaping @MainActor (CorrectionResult) -> Void
    ) {
        pendingState.lock.withLock {
            pendingState.task?.cancel()
            pendingState.task = Task {
                do {
                    try Task.checkCancellation()
                    let text: String
                    let bundleID: String?
                    var replacementRange: CFRange? = nil
                    if let pid = frontAppPID {
                        do {
                            text = try await AccessibilityBridge.shared.fetchSelectedText(fromPID: pid)
                        } catch CorrectionError.noTextSelected {
                            let (fallbackText, range) = try await AccessibilityBridge.shared.fetchTextOrLineAtCursor(fromPID: pid)
                            text = fallbackText
                            replacementRange = range
                        }
                        bundleID = await AppDetector.shared.frontAppBundleID(forPID: pid)
                    } else {
                        do {
                            text = try await AccessibilityBridge.shared.fetchSelectedText()
                        } catch CorrectionError.noTextSelected {
                            let pid = AccessibilityBridge.lastKnownFrontAppPID
                            let (fallbackText, range) = try await AccessibilityBridge.shared.fetchTextOrLineAtCursor(fromPID: pid)
                            text = fallbackText
                            replacementRange = range
                        }
                        bundleID = await AccessibilityBridge.shared.frontAppBundleID()
                    }
                    try Task.checkCancellation()
                    guard !text.isEmpty else {
                        await MainActor.run { SuggestionPanelController.shared.showError(.noTextSelected) }
                        return
                    }

                    if let id = bundleID {
                        let excluded = await MainActor.run { PreferencesStore.shared.isExcluded(bundleID: id) }
                        guard !excluded else { return }
                    }

                    let language = await MainActor.run { PreferencesStore.shared.language }
                    let detectedTone = await ToneDetector.shared.detect(text: text, language: language)

                    let resolved = await MainActor.run {
                        let prefs = PreferencesStore.shared
                        return RuleResolver.resolve(
                            appBundleID: bundleID,
                            customPrompts: prefs.customPrompts,
                            appRules: prefs.appRules
                        )
                    }

                    try Task.checkCancellation()
                    let rawResult = try await action(text, resolved, replacementRange, detectedTone)
                    let finalResult = CorrectionResult(
                        original: rawResult.originalText,
                        corrected: rawResult.correctedText,
                        modelID: rawResult.modelID,
                        explanation: rawResult.explanation,
                        confidence: rawResult.confidence,
                        customInstruction: rawResult.customInstruction,
                        promptType: rawResult.promptType,
                        replacementRange: replacementRange,
                        detectedTone: detectedTone.rawValue)
                    try Task.checkCancellation()
                    await MainActor.run { onSuccess(finalResult) }
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
}
