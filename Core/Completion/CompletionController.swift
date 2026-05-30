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
    private var currentContextKeys: [String] = []   // learning keys for the shown completion
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

        // Snippet expansion: trailing token matches a saved abbreviation → Tab expands it.
        if ax.caretRect != .zero {
            let token = String(ax.preContext.reversed().prefix { !$0.isWhitespace }.reversed())
            if token.count >= 2, token.count <= 30,
               let raw = await SnippetStore.shared.expansion(for: token) {
                let expansion = SnippetExpander.expand(raw)
                current = CompletionSuggestion(text: expansion, kind: .replaceLastWord(wrong: token))
                currentPID = pid
                TabInterceptor.setSuggestionVisible(true)
                overlay.show(text: expansion.count > 30 ? String(expansion.prefix(30)) + "…" : expansion, atCaretRect: ax.caretRect)
                Logger.infra.debug("completion: snippet \(token, privacy: .public)")
                return
            }
        }

        // Emoji: typing ":shortcode" → Tab replaces it with the emoji.
        if ax.caretRect != .zero, let em = EmojiCompletion.match(preContext: ax.preContext, skinTone: PreferencesStore.shared.completionEmojiSkinTone) {
            current = CompletionSuggestion(text: em.emoji, kind: .replaceLastWord(wrong: em.shortcode))
            currentPID = pid
            TabInterceptor.setSuggestionVisible(true)
            overlay.show(text: em.emoji, atCaretRect: ax.caretRect)
            Logger.infra.debug("completion: emoji \(em.shortcode, privacy: .public) -> \(em.emoji, privacy: .public)")
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

        // Learned (Cotypist-style, n-gram): if this context was completed before, suggest it INSTANTLY
        // — no model call → faster + personalized for your recurring phrases.
        let contextKeys = CompletionLearningStore.keys(forContext: ax.preContext)
        if !contextKeys.isEmpty,
           let learned = await CompletionLearningStore.shared.learnedSuggestion(keys: contextKeys),
           let cleaned = CompletionPostprocessor.clean(raw: learned.text, preContext: ax.preContext, maxWords: PreferencesStore.shared.maxCompletionLength * 3, allowCode: allowCode) {
            current = CompletionSuggestion(text: cleaned, kind: .insert)
            currentPID = pid
            currentContextKeys = contextKeys
            await CompletionLearningStore.shared.noteShown(key: learned.key)
            TabInterceptor.setSuggestionVisible(true)
            overlay.show(text: cleaned, atCaretRect: ax.caretRect)
            Logger.infra.debug("completion: learned suggestion for '\(learned.key, privacy: .public)'")
            return
        }

        // Enrich the prefix with on-screen context (the conversation/email above the field, which is
        // NOT in the text field) so suggestions are grounded, not "pulled from a hat". The user's own
        // text stays LAST so the model continues IT. Screen OCR is cached/throttled (anti-stutter).
        var contextParts: [String] = []
        // Personalization (imported from Cotypist or set by the user) conditions the base model's voice.
        let userPrompt = PreferencesStore.shared.completionUserPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !userPrompt.isEmpty { contextParts.append(userPrompt) }
        if PreferencesStore.shared.completionUseClipboardContext,
           let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !clip.isEmpty, clip.count <= 400 {
            contextParts.append(String(clip.prefix(400)))
        }
        if PreferencesStore.shared.completionUseScreenContext {
            let screen = await ScreenContextProvider.shared.currentContext(pid: pid)
            if !screen.isEmpty { contextParts.append(screen) }
        }
        // User's own text stays LAST so the model continues IT.
        let preContext = contextParts.isEmpty ? ax.preContext : (contextParts + [ax.preContext]).joined(separator: "\n\n")

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
        currentContextKeys = contextKeys
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
        let keys = currentContextKeys
        clearSuggestion()
        Task {
            switch kind {
            case .insert:
                _ = await AccessibilityBridge.shared.insertCompletion(text, pid: pid)
                if !keys.isEmpty { await CompletionLearningStore.shared.record(keys: keys, accepted: text) }
            case .replaceLastWord(let wrong):
                _ = await AccessibilityBridge.shared.replaceLastWord(wrong: wrong, with: text, pid: pid)
            }
        }
    }

    /// Partial accept — insert the first word only, then re-suggest from the new position.
    /// Only meaningful for completions; a typo fix has no "partial", so it accepts fully.
    func acceptPartial() {
        guard let s = current, currentPID != 0 else { return }
        guard case .insert = s.kind else { acceptFull(); return }
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
        currentContextKeys = []
        TabInterceptor.setSuggestionVisible(false)
        overlay.hide()
    }
}
