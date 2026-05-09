import Foundation

private final class PendingState: @unchecked Sendable {
    let lock = NSLock()
    var task: Task<Void, Never>?
}

struct TextCheckCoordinator: Sendable {
    static let shared = TextCheckCoordinator()

    private let pendingState = PendingState()

    func checkSelectedText() {
        performCheck { text, resolved in
            try await RequestQueue.shared.enqueue(
                text: text,
                type: .grammar,
                priority: .manual,
                overrideServiceType: resolved.serviceType,
                overrideCustomPrompt: resolved.prompt
            )
        } onSuccess: { result in
            SuggestionPanelController.shared.show(result: result)
        }
    }

    func checkSelectedText(fromPID pid: pid_t) {
        performCheck(frontAppPID: pid) { text, resolved in
            try await RequestQueue.shared.enqueue(
                text: text,
                type: .grammar,
                priority: .manual,
                overrideServiceType: resolved.serviceType,
                overrideCustomPrompt: resolved.prompt
            )
        } onSuccess: { result in
            SuggestionPanelController.shared.show(result: result)
        }
    }

    func checkFluency() {
        guard UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.isFluencyCheckingEnabled) else { return }
        performCheck { text, resolved in
            let serviceType = resolved.serviceType ?? LLMServiceFactory.resolveFluencyServiceType()
            return try await RequestQueue.shared.enqueue(
                text: text,
                type: .fluency,
                priority: .manual,
                overrideServiceType: serviceType,
                overrideCustomPrompt: resolved.prompt
            )
        } onSuccess: { result in
            SuggestionPanelController.shared.showFluency(result: result)
        }
    }

    func checkFluency(fromPID pid: pid_t) {
        guard UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.isFluencyCheckingEnabled) else { return }
        performCheck(frontAppPID: pid) { text, resolved in
            let serviceType = resolved.serviceType ?? LLMServiceFactory.resolveFluencyServiceType()
            return try await RequestQueue.shared.enqueue(
                text: text,
                type: .fluency,
                priority: .manual,
                overrideServiceType: serviceType,
                overrideCustomPrompt: resolved.prompt
            )
        } onSuccess: { result in
            SuggestionPanelController.shared.showFluency(result: result)
        }
    }

    func openFloatingEditor() async {
        await MainActor.run {
            FloatingEditorController.shared.show()
        }
    }

    private func performCheck(
        frontAppPID: pid_t? = nil,
        action: @escaping @Sendable (String, (serviceType: ServiceType?, prompt: CustomPrompt?)) async throws -> CorrectionResult,
        onSuccess: @escaping @MainActor (CorrectionResult) -> Void
    ) {
        let task = Task {
            do {
                let text: String
                let bundleID: String?
                if let pid = frontAppPID {
                    text = try await AccessibilityBridge.shared.fetchSelectedText(fromPID: pid)
                    bundleID = await AppDetector.shared.frontAppBundleID(forPID: pid)
                } else {
                    text = try await AccessibilityBridge.shared.fetchSelectedText()
                    bundleID = await AccessibilityBridge.shared.frontAppBundleID()
                }
                guard !text.isEmpty else {
                    await MainActor.run { SuggestionPanelController.shared.showError(.noTextSelected) }
                    return
                }

                if let id = bundleID {
                    let excluded = await MainActor.run { PreferencesStore.shared.isExcluded(bundleID: id) }
                    guard !excluded else { return }
                }

                let resolved = await MainActor.run {
                    let prefs = PreferencesStore.shared
                    return RuleResolver.resolve(
                        appBundleID: bundleID,
                        customPrompts: prefs.customPrompts,
                        appRules: prefs.appRules
                    )
                }

                let result = try await action(text, resolved)
                await MainActor.run { onSuccess(result) }
            } catch let error as CorrectionError {
                await MainActor.run { SuggestionPanelController.shared.showError(error) }
            } catch {
                await MainActor.run { SuggestionPanelController.shared.showError(.outputParsingFailed(raw: error.localizedDescription)) }
            }
        }
        pendingState.lock.withLock {
            pendingState.task?.cancel()
            pendingState.task = task
        }
    }
}
