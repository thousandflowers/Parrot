import SwiftUI
import Cocoa

enum SuggestionState: Sendable {
    case loading
    case suggestion(CorrectionResult, explanation: String? = nil, isLoadingExplanation: Bool = false)
    case fluencySuggestion(CorrectionResult, explanation: String? = nil, isLoadingExplanation: Bool = false)
    case noErrors
    case error(CorrectionError)
    case textTooLong(length: Int, maxLength: Int)
}

@MainActor
final class SuggestionPanelController {
    static let shared = SuggestionPanelController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<SuggestionView>?
    private var currentResult: CorrectionResult?
    private var currentState: SuggestionState?
    private var explanationTask: Task<Void, Never>?

    private init() {}

    // ... (animateIn, animateOut, clampToScreen stay same)

    private func showOrUpdate(result: CorrectionResult?, state: SuggestionState) {
        self.currentResult = result
        self.currentState = state
        
        let view = SuggestionView(
            result: result,
            state: state,
            onApply: { [weak self] in self?.applyCorrection() },
            onExplain: { [weak self] in self?.requestExplanation() },
            onDismiss: { [weak self] in self?.close() }
        )

        if let hv = hostingView {
            hv.rootView = view
        } else {
            panel = createPanel(with: view)
            
            let mouseLoc = NSEvent.mouseLocation
            let panelSize = panel?.frame.size ?? NSSize(width: 400, height: 220)
            let origin = clampToScreen(NSPoint(x: mouseLoc.x + 20, y: mouseLoc.y - 20), size: panelSize)
            panel?.setFrameOrigin(origin)
            panel?.orderFrontRegardless()
            animateIn(panel!)
        }
    }

    func show(result: CorrectionResult) {
        let state: SuggestionState = result.hasChanges ? .suggestion(result) : .noErrors
        showOrUpdate(result: result, state: state)
    }

    func showFluency(result: CorrectionResult) {
        let state: SuggestionState = result.hasChanges ? .fluencySuggestion(result) : .noErrors
        showOrUpdate(result: result, state: state)
    }

    func showLoading() {
        showOrUpdate(result: nil, state: .loading)
    }

    func showError(_ error: CorrectionError) {
        showOrUpdate(result: nil, state: .error(error))
    }

    private func createPanel(with view: SuggestionView) -> NSPanel {
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

        let hv = NSHostingView(rootView: view)
        hostingView = hv
        panel.contentView = hv

        return panel
    }

    private func applyCorrection() {
        guard let result = currentResult else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await AccessibilityBridge.shared.replaceSelectedText(with: result.correctedText)
                self.close()
            } catch {
                self.showError(error as? CorrectionError ?? .textExtractionFailed(appName: "unknown"))
            }
        }
    }

    private func requestExplanation() {
        guard let current = currentResult, let state = currentState else { return }
        explanationTask?.cancel()

        // Update state to loading explanation
        switch state {
        case .suggestion(let res, _, _):
            showOrUpdate(result: res, state: .suggestion(res, explanation: nil, isLoadingExplanation: true))
        case .fluencySuggestion(let res, _, _):
            showOrUpdate(result: res, state: .fluencySuggestion(res, explanation: nil, isLoadingExplanation: true))
        default: break
        }

        explanationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await withTimeout(seconds: 30) {
                    try await LLMServiceFactory.make().explain(
                        original: current.originalText,
                        corrected: current.correctedText
                    )
                }
                guard !Task.isCancelled else { return }
                guard !result.isEmpty else {
                    self.showError(.outputParsingFailed(raw: "empty explanation"))
                    return
                }

                // Update state with result
                switch self.currentState {
                case .suggestion(let res, _, _):
                    self.showOrUpdate(result: res, state: .suggestion(res, explanation: result, isLoadingExplanation: false))
                case .fluencySuggestion(let res, _, _):
                    self.showOrUpdate(result: res, state: .fluencySuggestion(res, explanation: result, isLoadingExplanation: false))
                default: break
                }
            } catch {
                self.showError(error as? CorrectionError ?? .serverTimeout)
            }
        }
    }

    func close() {
        explanationTask?.cancel()
        guard let panel = panel else { return }
        self.panel = nil
        self.hostingView = nil
        self.currentState = nil
        animateOut(panel) {
            panel.orderOut(nil)
        }
    }
}
