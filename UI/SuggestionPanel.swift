import SwiftUI
import Cocoa

enum SuggestionState: Sendable {
    case loading
    case streaming(original: String, current: String)
    case suggestion(CorrectionResult, explanation: String? = nil, isLoadingExplanation: Bool = false)
    case fluencySuggestion(CorrectionResult, explanation: String? = nil, isLoadingExplanation: Bool = false)
    case noErrors
    case error(CorrectionError)
    case textTooLong(length: Int, maxLength: Int)
    case applied(CorrectionResult)
    case modelMissing
}

// On macOS 26, NSHostingView.updateConstraints → updateWindowContentSizeExtremaIfNecessary
// triggers graphDidChange → requestUpdate → needsUpdateConstraints = true while already
// inside updateConstraints. AppKit's re-entrancy guard throws NSGenericException.
// Fix: DEFER the re-entrant write (don't drop it) — SwiftUI needs it to complete rendering.
// The deferred async write runs after the current constraint pass, so AppKit accepts it.
final class FixedSizeHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) { super.init(rootView: rootView) }
    required init?(coder: NSCoder) { fatalError() }

    private var isInUpdateConstraints = false

    override func updateConstraints() {
        isInUpdateConstraints = true
        defer { isInUpdateConstraints = false }
        super.updateConstraints()
    }

    override var needsUpdateConstraints: Bool {
        get { super.needsUpdateConstraints }
        set {
            if isInUpdateConstraints {
                // Defer re-entrant write until after the current pass completes.
                let v = newValue
                DispatchQueue.main.async { [weak self] in
                    self?.needsUpdateConstraints = v
                }
                return
            }
            super.needsUpdateConstraints = newValue
        }
    }
}

@MainActor
final class SuggestionPanelController {
    static let shared = SuggestionPanelController()

    private var panel: NSPanel?
    private var hostingView: FixedSizeHostingView<SuggestionView>?
    private var spanPanel: NSPanel?
    private var spanHostingView: NSHostingView<SpanSuggestionView>?
    private var currentResult: CorrectionResult?
    private var currentState: SuggestionState?
    private var explanationTask: Task<Void, Never>?
    private var undoTask: Task<Void, Never>?
    private var clickMonitor: Any?
    private var appObserver: NSObjectProtocol?

    private init() {
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != "com.thousandflowers.parrot" else { return }
            Task { @MainActor in self?.close() }
        }
    }

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
        let screen = NSScreen.screens.first(where: { $0.frame.contains(origin) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return origin }
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
            onCustomAction: { [weak self] promptText in self?.applyCustomAction(promptText: promptText) },
            onIgnoreWord: { [weak self] word in self?.ignoreWord(word) },
            onRunFlow: { [weak self] flow in self?.runFlow(flow) }
        )

        if let hv = hostingView {
            // Update rootView — SwiftUI reconciles safely within the existing constraint context.
            // Never replace contentView on a visible/animated window: AutoLayout throws during
            // the subsequent display cycle → AppKit _crashOnException → SIGTRAP (signal 5).
            hv.rootView = view
            panel?.orderFrontRegardless()
        } else {
            let newPanel = createPanel(with: view)
            panel = newPanel
            let origin = panelOrigin(panelSize: newPanel.frame.size)
            newPanel.setFrameOrigin(origin)
            newPanel.orderFrontRegardless()
            animateIn(newPanel)
            installClickMonitor(for: newPanel)
        }
    }

    func show(result: CorrectionResult) {
        let state: SuggestionState = result.hasChanges ? .suggestion(result) : .noErrors
        MenuBarParrot.shared.setState(result.hasChanges ? .excited : .approving)
        showOrUpdate(result: result, state: state)
    }

    func showFluency(result: CorrectionResult) {
        let state: SuggestionState = result.hasChanges ? .fluencySuggestion(result) : .noErrors
        MenuBarParrot.shared.setState(result.hasChanges ? .excited : .approving)
        showOrUpdate(result: result, state: state)
    }

    var isLoading: Bool {
        if case .loading = currentState { return true }
        return false
    }

    func showLoading() {
        showOrUpdate(result: nil, state: .loading)
    }

    private var streamingTask: Task<Void, Never>?

    func showOrUpdateStreaming(original: String, current: String) {
        showOrUpdate(result: nil, state: .streaming(original: original, current: current))
    }

    func startStreaming(original: String, promptType: PromptType) {
        streamingTask?.cancel()
        streamingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var accumulated = ""
            showOrUpdate(result: nil, state: .streaming(original: original, current: ""))
            do {
                let service = LLMServiceFactory.make()
                for try await chunk in service.streamCorrect(text: original, promptType: promptType) {
                    guard !Task.isCancelled else { return }
                    accumulated = chunk
                    showOrUpdate(result: nil, state: .streaming(original: original, current: accumulated))
                }
                // Streaming complete — build final result and show as suggestion
                let finalResult = CorrectionResult(
                    original: original,
                    corrected: accumulated.isEmpty ? original : accumulated,
                    modelID: "streaming",
                    promptType: promptType.label
                )
                let state: SuggestionState = finalResult.hasChanges ? .suggestion(finalResult) : .noErrors
                showOrUpdate(result: finalResult, state: state)
            } catch {
                guard !Task.isCancelled else { return }
                showError(error as? CorrectionError ?? .outputParsingFailed(raw: error.localizedDescription))
            }
        }
    }

    func showError(_ error: CorrectionError) {
        if case .modelNotLoaded = error {
            showOrUpdate(result: nil, state: .modelMissing)
        } else {
            showOrUpdate(result: nil, state: .error(error))
        }
    }

    private func panelOrigin(panelSize: NSSize) -> NSPoint {
        let bounds = AccessibilityBridge.shared.lastSelectionBoundsSync
        if bounds != .zero {
            // Position below selected text; flip if too close to bottom edge
            let x = bounds.midX - panelSize.width / 2
            let belowY = bounds.minY - panelSize.height - 8
            let origin = NSPoint(x: x, y: belowY)
            let clamped = clampToScreen(origin, size: panelSize)
            // If clamping moved us up (panel was below screen), try above selection instead
            if clamped.y > belowY + 4 {
                let aboveY = bounds.maxY + 8
                return clampToScreen(NSPoint(x: x, y: aboveY), size: panelSize)
            }
            return clamped
        }
        let mouseLoc = NSEvent.mouseLocation
        return clampToScreen(NSPoint(x: mouseLoc.x + 20, y: mouseLoc.y - panelSize.height / 2), size: panelSize)
    }

    private func installClickMonitor(for targetPanel: NSPanel) {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak targetPanel] _ in
            guard let self, let targetPanel else { return }
            if !targetPanel.frame.contains(NSEvent.mouseLocation) {
                Task { @MainActor in self.close() }
            }
        }
    }

    private func createPanel(with view: SuggestionView) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 280),
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
        // Clamp size: prevents NSHostingView.updateAnimatedWindowSize from calling setFrame
        // with a different value during windowDidLayout, which triggers re-entrant constraint
        // updates and crash on macOS 26. sizingOptions=[] alone is insufficient on macOS 26.
        let fixedSize = NSSize(width: 340, height: 280)
        panel.minSize = fixedSize
        panel.maxSize = fixedSize

        let hv = FixedSizeHostingView(rootView: view)
        hv.sizingOptions = []
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
                Task { await HistoryStore.shared.add(result: result) }
                self.showOrUpdate(result: result, state: .applied(result))
                self.undoTask?.cancel()
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

    func ignoreWord(_ word: String) {
        IgnoreList.ignore(word)
    }

    func runFlow(_ flow: Flow) {
        guard let result = currentResult else { return }
        showOrUpdate(result: nil, state: .loading)
        Task { [weak self] in
            guard let self else { return }
            var text = result.originalText
            var lastResult: CorrectionResult?
            do {
                for step in flow.steps {
                    let newResult = try await RequestQueue.shared.enqueue(
                        text: text,
                        type: step.promptType,
                        priority: .manual,
                        overrideServiceType: nil,
                        overrideCustomPrompt: step.customInstruction.map { CustomPrompt(id: UUID(), name: "Flow Step", template: $0, checkType: .custom) }
                    )
                    text = newResult.correctedText
                    lastResult = newResult
                }
                guard let final = lastResult else { close(); return }
                let combined = CorrectionResult(
                    original: result.originalText,
                    corrected: final.correctedText,
                    modelID: "flow:\(flow.name)",
                    promptType: "flow"
                )
                showOrUpdate(result: combined, state: .suggestion(combined))
            } catch {
                showError(error as? CorrectionError ?? .outputParsingFailed(raw: error.localizedDescription))
            }
        }
    }

    func showSpans(result: CorrectionResult, spans: [CorrectionSpan]) {
        close()
        let view = SpanSuggestionView(
            original: result.originalText,
            spans: spans
        ) { [weak self] acceptedSpans in
            guard let self else { return }
            // Accept-all: use authoritative corrected text (avoids offset inaccuracies in span map).
            // Partial accept: reconstruct via SpanApplicator (rule spans are offset-correct; LLM spans
            // may be slightly off if rule corrections changed the text, but partial accept is rare).
            let corrected: String
            if acceptedSpans.count == spans.count {
                corrected = result.correctedText
            } else {
                corrected = SpanApplicator.apply(spans: acceptedSpans, to: result.originalText)
            }
            var finalResult = CorrectionResult(
                original: result.originalText,
                corrected: corrected,
                modelID: result.modelID,
                confidence: result.confidence,
                promptType: result.promptType
            )
            finalResult.replacementRange = result.replacementRange
            finalResult.anchorRect = result.anchorRect
            self.applyAndClose(result: finalResult)
        } onDismiss: { [weak self] in
            self?.closeSpanPanel()
        }

        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 460),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = true
        newPanel.isMovableByWindowBackground = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hv = NSHostingView(rootView: view)
        hv.sizingOptions = []
        spanHostingView = hv
        newPanel.contentView = hv
        spanPanel = newPanel

        let origin = panelOrigin(panelSize: newPanel.frame.size)
        newPanel.setFrameOrigin(origin)
        newPanel.orderFrontRegardless()
        animateIn(newPanel)
    }

    private func applyAndClose(result: CorrectionResult) {
        closeSpanPanel()
        MenuBarParrot.shared.setState(.approving)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await AccessibilityBridge.shared.replaceSelectedText(with: result.correctedText)
                Task { await HistoryStore.shared.add(result: result) }
                if result.promptType == PromptType.expand.label {
                    Task { await self.learnContactFromExpand(result: result) }
                }
            } catch {
                showError(error as? CorrectionError ?? .textExtractionFailed(appName: "unknown"))
            }
        }
    }

    private func learnContactFromExpand(result: CorrectionResult) async {
        guard let inferred = await ContactInferrer.extract(from: result.correctedText),
              let name = inferred.name else { return }
        var profile = await ContactStore.shared.findInText(name)
            ?? ContactProfile(name: name)
        profile.name = name
        if let role = inferred.role        { profile.role = role }
        profile.formality = inferred.formality
        if let s = inferred.salutation     { profile.salutation = s }
        if let c = inferred.closing        { profile.closing = c }
        profile.lastSeen = Date()
        await ContactStore.shared.upsert(profile)
    }

    private func closeSpanPanel() {
        guard let panel = spanPanel else { return }
        spanPanel = nil
        spanHostingView = nil
        animateOut(panel) { panel.orderOut(nil) }
    }

    func close() {
        undoTask?.cancel()
        undoTask = nil
        explanationTask?.cancel()
        explanationTask = nil
        streamingTask?.cancel()
        streamingTask = nil
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        closeSpanPanel()
        MenuBarParrot.shared.setState(.idle)
        guard let panel = panel else { return }
        self.panel = nil
        self.hostingView = nil
        self.currentState = nil
        animateOut(panel) {
            panel.orderOut(nil)
        }
    }
}
