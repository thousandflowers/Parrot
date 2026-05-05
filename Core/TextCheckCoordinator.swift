import Foundation

struct TextCheckCoordinator: Sendable {
    static let shared = TextCheckCoordinator()

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

    func checkFluency() {
        guard UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.isFluencyCheckingEnabled) else { return }
        performCheck { text, resolved in
            let serviceType = resolved.serviceType ?? LLMServiceFactory.resolveFluencyServiceType()
            let service = LLMServiceFactory.make(with: serviceType)
            return try await service.correctFluency(text: text)
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
        action: @escaping @Sendable (String, (serviceType: ServiceType?, prompt: CustomPrompt?)) async throws -> CorrectionResult,
        onSuccess: @escaping @MainActor (CorrectionResult) -> Void
    ) {
        Task {
            do {
                let text = try await AccessibilityBridge.shared.fetchSelectedText()
                guard !text.isEmpty else {
                    await MainActor.run { SuggestionPanelController.shared.showError(.noTextSelected) }
                    return
                }

                let bundleID = await AccessibilityBridge.shared.frontAppBundleID()
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
    }
}
