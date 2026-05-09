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
    private var currentResult: CorrectionResult?
    private var explanationTask: Task<Void, Never>?

    private init() {}

    private func clampToScreen(_ origin: NSPoint, size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return origin }
        let frame = screen.visibleFrame
        let clampedX = min(max(origin.x, frame.minX), frame.maxX - size.width)
        let clampedY = min(max(origin.y, frame.minY), frame.maxY - size.height)
        return NSPoint(x: clampedX, y: clampedY)
    }

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
        let panelSize = panel?.frame.size ?? NSSize(width: 400, height: 220)
        let origin = clampToScreen(NSPoint(x: mouseLoc.x + 20, y: mouseLoc.y - 20), size: panelSize)
        panel?.setFrameOrigin(origin)
        panel?.orderFrontRegardless()
    }

    func showFluency(result: CorrectionResult) {
        self.currentResult = result

        if panel == nil {
            panel = createPanel(with: result, stateFor: { .fluencySuggestion($0) })
        } else {
            let hostingView = NSHostingView(rootView: SuggestionView(
                result: result,
                state: .fluencySuggestion(result),
                onApply: { [weak self] in self?.applyCorrection() },
                onExplain: { [weak self] in self?.requestExplanation() },
                onDismiss: { [weak self] in self?.close() }
            ))
            panel?.contentView = hostingView
        }

        let mouseLoc = NSEvent.mouseLocation
        let panelSize = panel?.frame.size ?? NSSize(width: 400, height: 220)
        let origin = clampToScreen(NSPoint(x: mouseLoc.x + 20, y: mouseLoc.y - 20), size: panelSize)
        panel?.setFrameOrigin(origin)
        panel?.orderFrontRegardless()
    }

    func showLoading() {
        panel?.orderOut(nil)
        let panel = createPanel(loading: true)
        self.panel = panel

        let mouseLoc = NSEvent.mouseLocation
        let panelSize = panel.frame.size
        let origin = clampToScreen(NSPoint(x: mouseLoc.x + 20, y: mouseLoc.y - 20), size: panelSize)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    func showError(_ error: CorrectionError) {
        panel?.orderOut(nil)
        panel = nil
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
        let panelSize = panel.frame.size
        let origin = clampToScreen(NSPoint(x: mouseLoc.x + 20, y: mouseLoc.y - 20), size: panelSize)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    private func createPanel(with result: CorrectionResult? = nil, loading: Bool = false, stateFor: ((CorrectionResult) -> SuggestionState)? = nil) -> NSPanel {
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
        } else if let result = result, let mapper = stateFor {
            state = result.hasChanges ? mapper(result) : .noErrors
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
                guard !result.isEmpty, let panel = self.panel else { return }

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
        panel?.orderOut(nil)
        panel = nil
    }
}
