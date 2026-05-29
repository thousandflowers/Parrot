import AppKit
import OSLog

/// Orchestrates the live inline-completion loop: debounce text changes, read caret context,
/// ask the engine, show the ghost overlay, and apply on accept. Main-actor isolated.
@MainActor
final class CompletionController {
    static let shared = CompletionController()

    private let overlay = CompletionOverlayWindow()
    private var current: CompletionSuggestion?
    private var currentPID: pid_t = 0
    private var debounce: Task<Void, Never>?

    private init() {}

    var isEnabled: Bool { PreferencesStore.shared.inlineCompletionEnabled }
    var hasSuggestion: Bool { current != nil }

    /// Called on every focused-text change (from `RealtimeMonitor`'s AX observer).
    func textChanged() {
        guard isEnabled else { return }
        clearSuggestion()
        debounce?.cancel()
        let ms = max(120, PreferencesStore.shared.completionDebounceMs)
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(ms))
            guard !Task.isCancelled else { return }
            await self?.requestSuggestion()
        }
    }

    private func requestSuggestion() async {
        // The Tab tap can only install once Accessibility is trusted. The user often grants it
        // AFTER launch, so the launch-time start() bailed. Retry here (idempotent): once we are
        // reading context successfully, AX is trusted, so the tap installs and — crucially — this
        // is where IOHIDRequestAccess fires to put Parrot in the Input Monitoring list.
        TabInterceptor.shared.start()

        let pid = await AccessibilityBridge.shared.lastKnownFrontAppPID()
        guard pid != 0 else { return }
        if let id = await AppDetector.shared.frontAppBundleID(forPID: pid),
           PreferencesStore.shared.isExcluded(bundleID: id) { return }
        guard let ax = await AccessibilityBridge.shared.completionContext(pid: pid), !ax.isSecure else {
            Logger.infra.debug("completion: no usable focused field (or secure)")
            return
        }

        let context = CompletionContext(preContext: ax.preContext, postContext: ax.postContext,
                                        language: PreferencesStore.shared.language)
        Logger.infra.debug("completion: preContext tail=…\(String(ax.preContext.suffix(40)), privacy: .public)| post=\(String(ax.postContext.prefix(20)), privacy: .public)")
        guard context.isUsable else { return }
        let maxWords = PreferencesStore.shared.maxCompletionLength
        guard let suggestion = await CompletionEngine.shared.suggest(context: context, maxWords: maxWords) else {
            Logger.infra.debug("completion: engine returned no suggestion")
            return
        }
        guard !Task.isCancelled else { return }

        if ax.caretRect == .zero {
            Logger.infra.debug("completion: have suggestion but caret bounds .zero — app exposes no caret rect, cannot show ghost")
            return
        }

        current = suggestion
        currentPID = pid
        TabInterceptor.setSuggestionVisible(true)
        overlay.show(text: suggestion.text, atCaretRect: ax.caretRect)
        Logger.infra.debug("completion: showing \(suggestion.text, privacy: .public) at \(NSStringFromRect(ax.caretRect), privacy: .public)")
    }

    /// Tab — insert the whole suggestion.
    func acceptFull() {
        guard let s = current, currentPID != 0 else { return }
        let pid = currentPID
        let text = s.text
        clearSuggestion()
        Task { _ = await AccessibilityBridge.shared.insertCompletion(text, pid: pid) }
    }

    /// Partial accept — insert the first word only, then re-suggest from the new position.
    func acceptPartial() {
        guard let s = current, currentPID != 0 else { return }
        let pid = currentPID
        let word = s.firstWord
        clearSuggestion()
        Task {
            _ = await AccessibilityBridge.shared.insertCompletion(word, pid: pid)
            await MainActor.run { self.textChanged() }
        }
    }

    /// Clears any visible suggestion and cancels in-flight work.
    func dismiss() {
        debounce?.cancel()
        clearSuggestion()
        Task { await CompletionEngine.shared.cancelPending() }
    }

    private func clearSuggestion() {
        current = nil
        currentPID = 0
        TabInterceptor.setSuggestionVisible(false)
        overlay.hide()
    }
}
