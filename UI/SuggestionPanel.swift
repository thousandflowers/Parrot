import SwiftUI
import Cocoa

enum SuggestionState: Sendable {
    case loading
    case suggestion(CorrectionResult)
    case noErrors
    case error(CorrectionError)
    case textTooLong(length: Int, maxLength: Int)
}

@MainActor
final class SuggestionPanelController {
    static let shared = SuggestionPanelController()

    private var panel: NSPanel?
    private var currentResult: CorrectionResult?

    private init() {}

    func show(result: CorrectionResult) {
        self.currentResult = result

        if panel == nil {
            panel = createPanel(with: result)
        } else {
            let hostingView = NSHostingView(rootView: SuggestionView(
                result: result,
                state: .suggestion(result),
                onApply: { [weak self] in self?.applyCorrection() },
                onExplain: { [weak self] in self?.requestExplanation() },
                onDismiss: { [weak self] in self?.close() }
            ))
            panel?.contentView = hostingView
        }

        let mouseLoc = NSEvent.mouseLocation
        panel?.setFrameOrigin(NSPoint(x: mouseLoc.x + 20, y: mouseLoc.y - 20))
        panel?.orderFrontRegardless()
    }

    func showLoading() {
        panel?.orderOut(nil)  // Close old panel before creating new one
        let panel = createPanel(loading: true)
        self.panel = panel

        let mouseLoc = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: mouseLoc.x + 20, y: mouseLoc.y - 20))
        panel.orderFrontRegardless()
    }

    func showError(_ error: CorrectionError) {
        let panel = createPanel(loading: false)
        self.panel = panel

        let hostingView = NSHostingView(rootView: SuggestionView(
            result: nil,
            state: .error(error),
            onApply: {},
            onExplain: {},
            onDismiss: { [weak self] in self?.close() }
        ))
        panel.contentView = hostingView

        let mouseLoc = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: mouseLoc.x + 20, y: mouseLoc.y - 20))
        panel.orderFrontRegardless()
    }

    private func createPanel(with result: CorrectionResult? = nil, loading: Bool = false) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let state: SuggestionState
        if loading {
            state = .loading
        } else if let result = result {
            state = result.hasChanges ? .suggestion(result) : .noErrors
        } else {
            state = .noErrors
        }

        let hostingView = NSHostingView(rootView: SuggestionView(
            result: result,
            state: state,
            onApply: { [weak self] in self?.applyCorrection() },
            onExplain: { [weak self] in self?.requestExplanation() },
            onDismiss: { [weak self] in self?.close() }
        ))
        panel.contentView = hostingView

        return panel
    }

    private func applyCorrection() {
        guard let result = currentResult else { return }

        Task {
            do {
                try await AccessibilityBridge.shared.replaceSelectedText(with: result.correctedText)
                self.close()
            } catch {
                self.showError(error as? CorrectionError ?? .textExtractionFailed(appName: "unknown"))
            }
        }
    }

    private func requestExplanation() {
        guard let result = currentResult else { return }

        Task {
            do {
                let engine = PromptEngine(language: PreferencesStore.shared.language)
                let prompt = engine.buildExplainPrompt(original: result.originalText, corrected: result.correctedText)

                let explainResult = try await RequestQueue.shared.enqueue(
                    text: prompt,
                    type: .explain,
                    priority: .manual
                )

                guard let explanation = explainResult.explanation, !explanation.isEmpty else { return }

                let alert = NSAlert()
                alert.messageText = "Spiegazione"
                alert.informativeText = explanation
                alert.runModal()
            } catch {
                self.showError(error as? CorrectionError ?? .serverTimeout)
            }
        }
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}
