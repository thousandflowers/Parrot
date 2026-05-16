import SwiftUI
import Cocoa

enum SuggestionState: Sendable {
    case loading
    case streaming(originalText: String, accumulatedCorrected: String)
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
    private var explanationWindow: NSWindow?
    var lastCheckType: RetryCheckType?
    private var applyTask: Task<Void, Never>?
    private var autoDismissTask: Task<Void, Never>?

    enum RetryCheckType {
        case grammar(pid_t?)
        case fluency(pid_t?)
        case translation(pid_t?, language: String)
        case grammarThenFluency(pid_t?)
    }

    private init() {}

    private func clampToScreen(_ origin: NSPoint, size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return origin }
        let frame = screen.visibleFrame
        let clampedX = max(frame.minX, min(frame.maxX - size.width, origin.x))
        let clampedY = max(frame.minY, min(frame.maxY - size.height, origin.y))
        return NSPoint(x: clampedX, y: clampedY)
    }

    private func originNear(anchor: CGRect?, panelSize: NSSize) -> NSPoint {
        if let a = anchor {
            let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
            let x = a.midX - panelSize.width / 2
            let belowY = a.minY - panelSize.height - 8
            let y = belowY >= screen.minY ? belowY : a.maxY + 8
            return clampToScreen(NSPoint(x: x, y: y), size: panelSize)
        }
        let mouse = NSEvent.mouseLocation
        return clampToScreen(NSPoint(x: mouse.x + 20, y: mouse.y - 20), size: panelSize)
    }

    func show(result: CorrectionResult) {
        self.currentResult = result

        let isNew: Bool
        if panel == nil {
            panel = createPanel(with: result)
            isNew = true
        } else {
            isNew = false
            updateHostingView(result: result, state: .suggestion(result))
        }

        let panelSize = panel?.frame.size ?? NSSize(width: 400, height: 220)
        panel?.setFrameOrigin(originNear(anchor: result.anchorRect, panelSize: panelSize))
        guard let p = panel else { return }
        showPanel(p, animated: isNew)
    }

    func showStreaming(original: String, accumulated: String) {
        let state: SuggestionState = .streaming(originalText: original, accumulatedCorrected: accumulated)
        showOrUpdate(result: nil, state: state)
    }

    private func showOrUpdate(result: CorrectionResult?, state: SuggestionState) {
        if let p = panel {
            updateHostingView(result: result, state: state)
            showPanel(p, animated: false)
        } else {
            let p = createPanel(with: result, state: state)
            panel = p
            let panelSize = p.frame.size
            let mouseLoc = NSEvent.mouseLocation
            let origin = clampToScreen(NSPoint(x: mouseLoc.x + 20, y: mouseLoc.y - 20), size: panelSize)
            p.setFrameOrigin(origin)
            showPanel(p, animated: true)
        }
    }

    func showFluency(result: CorrectionResult) {
        self.currentResult = result

        let isNew: Bool
        if panel == nil {
            panel = createPanel(with: result, stateFor: { .fluencySuggestion($0) })
            isNew = true
        } else {
            isNew = false
            updateHostingView(result: result, state: .fluencySuggestion(result))
        }

        let panelSize = panel?.frame.size ?? NSSize(width: 400, height: 220)
        panel?.setFrameOrigin(originNear(anchor: result.anchorRect, panelSize: panelSize))
        guard let p = panel else { return }
        showPanel(p, animated: isNew)
    }

    func showLoading(checkType: RetryCheckType? = nil) {
        lastCheckType = checkType
        panel?.orderOut(nil)
        let panel = createPanel(loading: true)
        self.panel = panel

        let mouseLoc = NSEvent.mouseLocation
        let panelSize = panel.frame.size
        let origin = clampToScreen(NSPoint(x: mouseLoc.x + 20, y: mouseLoc.y - 20), size: panelSize)
        panel.setFrameOrigin(origin)
        showPanel(panel, animated: true)
    }

    func showError(_ error: CorrectionError) {
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        let panel = createPanel(loading: false)
        self.panel = panel

        updateHostingView(result: nil, state: .error(error))

        let mouseLoc = NSEvent.mouseLocation
        let panelSize = panel.frame.size
        let origin = clampToScreen(NSPoint(x: mouseLoc.x + 20, y: mouseLoc.y - 20), size: panelSize)
        panel.setFrameOrigin(origin)
        showPanel(panel, animated: true)
    }

    private func createPanel(with result: CorrectionResult? = nil, loading: Bool = false, state: SuggestionState? = nil, stateFor: ((CorrectionResult) -> SuggestionState)? = nil) -> NSPanel {
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

        let resolvedState: SuggestionState
        if let explicitState = state {
            resolvedState = explicitState
        } else if loading {
            resolvedState = .loading
        } else if let result = result, let mapper = stateFor {
            resolvedState = result.hasChanges ? mapper(result) : .noErrors
        } else if let result = result {
            resolvedState = result.hasChanges ? .suggestion(result) : .noErrors
        } else {
            resolvedState = .noErrors
        }

        let hostingView = NSHostingView(rootView: SuggestionView(
            result: result,
            state: resolvedState,
            onApply: { [weak self] in self?.applyCorrection() },
            onExplain: { [weak self] in self?.requestExplanation() },
            onDismiss: { [weak self] in self?.close() },
            onRetry: { [weak self] in self?.retryLastCheck() },
            onUpgradeToAI: { [weak self] in self?.upgradeToLLM() }
        ))
        self.hostingView = hostingView
        panel.contentView = hostingView

        return panel
    }

    private func applyCorrection() {
        guard let result = currentResult else { return }

        applyTask?.cancel()
        applyTask = Task {
            do {
                if let range = result.replacementRange, range.length > 0 {
                    let pid = AccessibilityBridge.lastKnownFrontAppPID
                    try await AccessibilityBridge.shared.replaceRange(range, with: result.correctedText, pid: pid)
                } else {
                    try await AccessibilityBridge.shared.replaceSelectedText(with: result.correctedText)
                }
                let bundleID = await AccessibilityBridge.shared.frontAppBundleID()
                await UndoHistoryStore.shared.add(UndoEntry(
                    id: UUID(),
                    originalText: result.originalText,
                    replacedText: result.correctedText,
                    bundleID: bundleID,
                    timestamp: Date()
                ))
                self.close()
            } catch {
                self.showError(error as? CorrectionError ?? .textExtractionFailed(appName: "unknown"))
            }
        }
    }

    private func requestExplanation() {
        guard let current = currentResult else { return }
        explanationTask?.cancel()

        explanationTask = Task { @MainActor [weak self] in
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

                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                    styleMask: [.titled, .closable, .resizable],
                    backing: .buffered,
                    defer: false
                )
                window.title = "Spiegazione"
                window.center()
                window.isReleasedWhenClosed = false

                let scrollView = NSScrollView()
                scrollView.hasVerticalScroller = true
                scrollView.autohidesScrollers = true
                scrollView.borderType = .noBorder

                let textView = NSTextView()
                textView.isEditable = false
                textView.isSelectable = true
                textView.isRichText = false
                textView.font = .systemFont(ofSize: NSFont.systemFontSize)
                textView.string = result
                textView.textContainer?.containerSize = NSSize(width: scrollView.bounds.width, height: .greatestFiniteMagnitude)
                textView.textContainer?.widthTracksTextView = true
                textView.backgroundColor = .clear

                scrollView.documentView = textView
                scrollView.contentView = scrollView.contentView
                scrollView.frame = window.contentView!.bounds
                scrollView.autoresizingMask = [.width, .height]

                window.contentView = scrollView
                self.explanationWindow = window
                window.alphaValue = 0
                window.makeKeyAndOrderFront(nil)
                await NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().alphaValue = 1
                }
            } catch {
                self.showError(error as? CorrectionError ?? .serverTimeout)
            }
        }
    }

    func closePanel() {
        explanationTask?.cancel()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    func showNoErrors() {
        guard let p = panel else { return }
        updateHostingView(result: nil, state: .noErrors)
        p.orderFrontRegardless()
        autoDismissTask?.cancel()
        autoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            self?.closePanel()
        }
    }

    func close() {
        explanationTask?.cancel()
        applyTask?.cancel()
        TextCheckCoordinator.shared.cancelPendingCheck()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        InlineHighlightController.shared.clear()
    }

    func retryLastCheck() {
        close()
        guard let checkType = lastCheckType else { return }
        switch checkType {
        case .grammar(let pid):
            if let pid = pid { TextCheckCoordinator.shared.checkSelectedText(fromPID: pid) }
            else { TextCheckCoordinator.shared.checkSelectedText() }
        case .fluency(let pid):
            if let pid = pid { TextCheckCoordinator.shared.checkFluency(fromPID: pid) }
            else { TextCheckCoordinator.shared.checkFluency() }
        case .translation(_, let language):
            TextCheckCoordinator.shared.translateSelectedText(to: language)
        case .grammarThenFluency(let pid):
            if let pid = pid { TextCheckCoordinator.shared.checkFluency(fromPID: pid) }
            else { TextCheckCoordinator.shared.checkGrammarThenFluency() }
        }
    }

    func upgradeToLLM() {
        guard let result = currentResult, result.source == .ruleBased else { return }
        close()
        TextCheckCoordinator.shared.checkLLMOnly(original: result.originalText)
    }

    private func updateHostingView(
        result: CorrectionResult?,
        state: SuggestionState
    ) {
        let view = SuggestionView(
            result: result,
            state: state,
            onApply: { [weak self] in self?.applyCorrection() },
            onExplain: { [weak self] in self?.requestExplanation() },
            onDismiss: { [weak self] in self?.close() },
            onRetry: { [weak self] in self?.retryLastCheck() },
            onUpgradeToAI: { [weak self] in self?.upgradeToLLM() }
        )
        if let hv = hostingView {
            hv.rootView = view
        } else {
            let hv = NSHostingView(rootView: view)
            hostingView = hv
            panel?.contentView = hv
        }
    }

    private func showPanel(_ panel: NSPanel, animated: Bool) {
        if animated {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }
    }
}
