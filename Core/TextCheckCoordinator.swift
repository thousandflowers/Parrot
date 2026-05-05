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

                let result = try await RequestQueue.shared.enqueue(
                    text: text,
                    type: .grammar,
                    priority: .manual
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

    func openFloatingEditor() async {
        await MainActor.run {
            FloatingEditorController.shared.show()
        }
    }
}
