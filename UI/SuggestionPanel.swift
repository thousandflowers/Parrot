import SwiftUI
import Cocoa

enum SuggestionState: Sendable {
    case loading
    case suggestion(CorrectionResult, explanation: String? = nil, isLoadingExplanation: Bool = false)
    case fluencySuggestion(CorrectionResult, explanation: String? = nil, isLoadingExplanation: Bool = false)
    case noErrors
    case error(CorrectionError)
    case textTooLong(length: Int, maxLength: Int)
    case applied(CorrectionResult)
    case modelMissing
}

@MainActor
final class SuggestionPanelController {
    static let shared = SuggestionPanelController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<SuggestionView>?
    private var currentResult: CorrectionResult?
    private var currentState: SuggestionState?
    private var explanationTask: Task<Void, Never>?
    private var undoTask: Task<Void, Never>?

    private init() {}

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func animateIn(_ panel: NSPanel) {
        guard !reduceMotion else { return }
        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }
    }

    private func animateOut(_ panel: NSPanel, completion: @escaping () -> Void) {
        guard !reduceMotion else { completion(); return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ctx.completionHandler = completion
            panel.animator().alphaValue = 0
        }
    }

    private func clampToScreen(_ origin: NSPoint, size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return origin }
        let frame = screen.visibleFrame
        let clampedX = max(frame.minX, min(frame.maxX - size.width, origin.x))
        let clampedY = max(frame.minY, min(frame.maxY - size.height, origin.y))
        return NSPoint(x: clampedX, y: clampedY)
    }

    private func showOrUpdate(result: CorrectionResult?, state: SuggestionState) {
        self.currentResult = result
        self.currentState = state

        let view = SuggestionView(
            result: result,
            state: state,
            onApply: { [weak self] in self?.applyCorrection() },
            onExplain: { [weak self] in self?.requestExplanation() },
            onDismiss: { [weak self] in self?.close() },
            onUndo: { [weak self] in self?.undoCorrection() },
            onTranslate: { [weak self] lang in self?.translate(to: lang) },
            onCustomAction: { [weak self] promptText in self?.applyCustomAction(promptText: promptText) }
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
        if case .modelNotLoaded = error {
            showOrUpdate(result: nil, state: .modelMissing)
        } else {
            showOrUpdate(result: nil, state: .error(error))
        }
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
                self.showOrUpdate(result: result, state: .applied(result))
                self.undoTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    await MainActor.run { self?.close() }
                }
            } catch {
                self.showError(error as? CorrectionError ?? .textExtractionFailed(appName: "unknown"))
            }
        }
    }

    private func undoCorrection() {
        undoTask?.cancel()
        undoTask = nil
        guard let result = currentResult else { close(); return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await AccessibilityBridge.shared.replaceSelectedText(with: result.originalText)
                let state: SuggestionState = result.hasChanges ? .suggestion(result) : .noErrors
                self.showOrUpdate(result: result, state: state)
            } catch {
                self.close()
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

    private func translate(to language: String) {
        guard let result = currentResult else { return }
        showOrUpdate(result: nil, state: .loading)
        Task { [weak self] in
            guard let self else { return }
            do {
                let newResult = try await RequestQueue.shared.enqueue(
                    text: result.originalText,
                    type: .translation(targetLanguage: language),
                    priority: .manual,
                    overrideServiceType: nil,
                    overrideCustomPrompt: nil
                )
                let finalResult = CorrectionResult(
                    original: result.originalText,
                    corrected: newResult.correctedText,
                    modelID: newResult.modelID,
                    promptType: "translation"
                )
                self.showOrUpdate(result: finalResult, state: .suggestion(finalResult))
            } catch {
                self.showError(error as? CorrectionError ?? .outputParsingFailed(raw: error.localizedDescription))
            }
        }
    }

    private func applyCustomAction(promptText: String) {
        guard let result = currentResult else { return }
        showOrUpdate(result: nil, state: .loading)
        Task { [weak self] in
            guard let self else { return }
            do {
                let customPrompt = CustomPrompt(id: UUID(), name: "Azione rapida", template: promptText, checkType: .custom)
                let newResult = try await RequestQueue.shared.enqueue(
                    text: result.originalText,
                    type: .grammar,
                    priority: .manual,
                    overrideServiceType: nil,
                    overrideCustomPrompt: customPrompt
                )
                let finalResult = CorrectionResult(
                    original: result.originalText,
                    corrected: newResult.correctedText,
                    modelID: newResult.modelID,
                    customInstruction: promptText
                )
                self.showOrUpdate(result: finalResult, state: finalResult.hasChanges ? .suggestion(finalResult) : .noErrors)
            } catch {
                self.showError(error as? CorrectionError ?? .outputParsingFailed(raw: error.localizedDescription))
            }
        }
    }

    func close() {
        undoTask?.cancel()
        undoTask = nil
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
