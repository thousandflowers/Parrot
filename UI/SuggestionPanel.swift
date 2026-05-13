import SwiftUI
import Cocoa

enum SuggestionState: Sendable {
    case loading
    case suggestion(CorrectionResult)
    case fluencySuggestion(CorrectionResult)
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
    private var explanationTask: Task<Void, Never>?

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

    private func showOrUpdate(result: CorrectionResult, state: SuggestionState) {
        self.currentResult = result
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
        }

        let mouseLoc = NSEvent.mouseLocation
        let panelSize = panel?.frame.size ?? NSSize(width: 400, height: 220)
        let origin = clampToScreen(NSPoint(x: mouseLoc.x + 20, y: mouseLoc.y - 20), size: panelSize)
        panel?.setFrameOrigin(origin)
        panel?.orderFrontRegardless()
        animateIn(panel!)
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
        let view = SuggestionView(
            result: nil,
            state: .loading,
            onApply: {},
            onExplain: {},
            onDismiss: { [weak self] in self?.close() }
        )
        panel?.orderOut(nil)
        hostingView = nil
        panel = createPanel(with: view)

        let mouseLoc = NSEvent.mouseLocation
        let panelSize = panel!.frame.size
        let origin = clampToScreen(NSPoint(x: mouseLoc.x + 20, y: mouseLoc.y - 20), size: panelSize)
        panel!.setFrameOrigin(origin)
        panel!.orderFrontRegardless()
        animateIn(panel!)
    }

    func showError(_ error: CorrectionError) {
        let view = SuggestionView(
            result: nil,
            state: .error(error),
            onApply: {},
            onExplain: {},
            onDismiss: { [weak self] in self?.close() }
        )
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        panel = createPanel(with: view)

        let mouseLoc = NSEvent.mouseLocation
        let panelSize = panel!.frame.size
        let origin = clampToScreen(NSPoint(x: mouseLoc.x + 20, y: mouseLoc.y - 20), size: panelSize)
        panel!.setFrameOrigin(origin)
        panel!.orderFrontRegardless()
        animateIn(panel!)
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
        guard let current = currentResult else { return }
        explanationTask?.cancel()

        explanationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await withTimeout(seconds: 30) {
                    try await LLMServiceFactory.make().explain(
                        original: current.originalText,
                        corrected: current.correctedText
                    )
                }
                guard !Task.isCancelled, let panel = self.panel else { return }
                guard !result.isEmpty else {
                    self.showError(.outputParsingFailed(raw: "empty explanation"))
                    return
                }

                let alert = NSAlert()
                alert.messageText = "Spiegazione"
                alert.informativeText = result
                alert.beginSheetModal(for: panel) { _ in }
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
        animateOut(panel) {
            panel.orderOut(nil)
        }
    }
}
