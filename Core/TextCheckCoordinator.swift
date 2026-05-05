import Foundation

/// Coordinates the text checking flow. Emits differentiated error notifications.
struct TextCheckCoordinator: Sendable {
    static let shared = TextCheckCoordinator()

    func checkSelectedText() {
        Task {
            do {
                let text = try await AccessibilityBridge.shared.fetchSelectedText()
                guard !text.isEmpty else {
                    await MainActor.run {
                        SuggestionPanelController.shared.showError(.noTextSelected)
                    }
                    return
                }

                guard let bundleID = await AccessibilityBridge.shared.frontAppBundleID() else { return }
                let excluded = await MainActor.run { PreferencesStore.shared.isExcluded(bundleID: bundleID) }
                guard !excluded else { return }
                let resolved = await MainActor.run {
                    let prefs = PreferencesStore.shared
                    return RuleResolver.resolve(
                        appBundleID: bundleID,
                        customPrompts: prefs.customPrompts,
                        appRules: prefs.appRules
                    )
                }

                let result = try await RequestQueue.shared.enqueue(
                    text: text,
                    type: .grammar,
                    priority: .manual,
                    overrideServiceType: resolved.serviceType,
                    overrideCustomPrompt: resolved.prompt
                )

                await MainActor.run {
                    SuggestionPanelController.shared.show(result: result)
                }
            } catch let error as CorrectionError {
                await MainActor.run {
                    SuggestionPanelController.shared.showError(error)
                }
            } catch {
                await MainActor.run {
                    SuggestionPanelController.shared.showError(.textExtractionFailed(appName: "unknown"))
                }
            }
        }
    }

    func checkFluency() {
        Task {
            do {
                let text = try await AccessibilityBridge.shared.fetchSelectedText()
                guard !text.isEmpty else {
                    await MainActor.run {
                        SuggestionPanelController.shared.showError(.noTextSelected)
                    }
                    return
                }

                let bundleID = await AccessibilityBridge.shared.frontAppBundleID()
                let excluded = await MainActor.run { PreferencesStore.shared.isExcluded(bundleID: bundleID ?? "") }
                guard !excluded else { return }
                let resolved = await MainActor.run {
                    let prefs = PreferencesStore.shared
                    return RuleResolver.resolve(
                        appBundleID: bundleID,
                        customPrompts: prefs.customPrompts,
                        appRules: prefs.appRules
                    )
                }

                let fluencyType = resolved.serviceType ?? LLMServiceFactory.resolveFluencyServiceType()
                let service = LLMServiceFactory.make(with: fluencyType)
                let result = try await service.correctFluency(text: text)

                await MainActor.run {
                    SuggestionPanelController.shared.showFluency(result: result)
                }
            } catch let error as CorrectionError {
                await MainActor.run {
                    SuggestionPanelController.shared.showError(error)
                }
            } catch {
                await MainActor.run {
                    SuggestionPanelController.shared.showError(.textExtractionFailed(appName: "unknown"))
                }
            }
        }
    }

    func openFloatingEditor() async {
        await MainActor.run {
            FloatingEditorController.shared.show()
        }
    }
}
