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
        let bundleID = await AppDetector.shared.frontAppBundleID(forPID: pid)
        if let id = bundleID, PreferencesStore.shared.isExcluded(bundleID: id) { return }
        let allowCode = await AppDetector.shared.isCodeEditor(bundleID: bundleID)
        guard let ax = await AccessibilityBridge.shared.completionContext(pid: pid), !ax.isSecure else {
            Logger.infra.debug("completion: no usable focused field (or secure)")
            return
        }

        // Typo fix: if the just-typed word is misspelled, Tab corrects it (instead of completing).
        // Skipped in code editors (identifiers aren't typos). Cheap on-device spell check, no LLM.
        if !allowCode, ax.caretRect != .zero,
           let fix = TypoFix.check(preContext: ax.preContext, language: PreferencesStore.shared.language) {
            current = CompletionSuggestion(text: fix.correction, kind: .replaceLastWord(wrong: fix.wrong))
            currentPID = pid
            TabInterceptor.setSuggestionVisible(true)
            overlay.show(text: "✓ " + fix.correction, atCaretRect: ax.caretRect)
            Logger.infra.debug("completion: typo fix \(fix.wrong, privacy: .public) -> \(fix.correction, privacy: .public)")
            return
        }

        // Enrich the prefix with on-screen context (the conversation/email above the field, which is
        // NOT in the text field) so suggestions are grounded, not "pulled from a hat". The user's own
        // text stays LAST so the model continues IT. Screen OCR is cached/throttled (anti-stutter).
        var preContext = ax.preContext
        if PreferencesStore.shared.completionUseScreenContext {
            let screen = await ScreenContextProvider.shared.currentContext(pid: pid)
            if !screen.isEmpty {
                preContext = screen + "\n\n" + ax.preContext
            }
        }

        let context = CompletionContext(preContext: preContext, postContext: ax.postContext,
                                        language: PreferencesStore.shared.language)
        Logger.infra.debug("completion: preContext tail=…\(String(ax.preContext.suffix(40)), privacy: .public)| screenCtx=\(PreferencesStore.shared.completionUseScreenContext)")
        guard CompletionContext(preContext: ax.preContext, postContext: ax.postContext, language: "").isUsable else { return }
        let maxWords = PreferencesStore.shared.maxCompletionLength
        guard let suggestion = await CompletionEngine.shared.suggest(context: context, maxWords: maxWords, allowCode: allowCode) else {
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

    /// Tab — accept the suggestion: insert a completion, or fix a typo by replacing the last word.
    func acceptFull() {
        guard let s = current, currentPID != 0 else { return }
        let pid = currentPID
        let text = s.text
        let kind = s.kind
        clearSuggestion()
        Task {
            switch kind {
            case .insert:
                _ = await AccessibilityBridge.shared.insertCompletion(text, pid: pid)
            case .replaceLastWord(let wrong):
                _ = await AccessibilityBridge.shared.replaceLastWord(wrong: wrong, with: text, pid: pid)
            }
        }
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
