import AppKit
import OSLog

private let kVK_Space: Int64 = 49

/// Orchestrates the live inline-completion loop: debounce text changes, read caret context,
/// ask the engine, show the ghost overlay, and apply on accept. Main-actor isolated.
@MainActor
final class CompletionController {
    static let shared = CompletionController()

    private let overlay = CompletionOverlayWindow()
    private var current: CompletionSuggestion?
    private var currentPID: pid_t = 0
    private var currentContextKeys: [String] = []   // learning keys for the shown completion
    private var suggestionGen: UInt64 = 0           // bumped each requestSuggestion(); stale reqs skip overlay show
    private var debounce: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var shownAt = Date.distantPast
    private var ignoreTextChangesUntil = Date.distantPast   // suppress the AX event our own accept-insert causes

    private let adaptive = AdaptiveDebounce()       // 40ms when paused → up to 200ms under fast typing
    private var lastKeystrokeAt = Date.distantPast
    private let cache = SuggestionCache()           // in-memory LRU → the <50ms hot path
    let typedBuffer = TypedInputBuffer()            // AX-blind fallback context (fed by TabInterceptor)
    private var lastBufferPID: pid_t = 0            // reset the typed buffer when the focused app changes
    private var lastAXFoundField = false            // did the previous AX query see a real text field?

    private init() {}

    // Gate on AppMode too: only Wren shows completion. Parrot starts RealtimeMonitor for live
    // correction, whose AX observer also calls textChanged() — without this gate Parrot would show
    // ghost text it has no Tab tap to accept (TabInterceptor is started only in Wren).
    var isEnabled: Bool { AppMode.current.showsCompletion && PreferencesStore.shared.inlineCompletionEnabled }
    var hasSuggestion: Bool { current != nil }

    /// Called on every focused-text change (from `RealtimeMonitor`'s AX observer).
    func textChanged() {
        guard isEnabled, !FocusMode.shared.isRawDraft else { return }
        // Ignore the field change WE caused by inserting an accepted word: otherwise the AX
        // value-changed event regenerates a fresh suggestion and clobbers the word-by-word Tab walk,
        // so pressing Tab a few times never lets you accept just part of the SAME suggestion (#3).
        if Date() < ignoreTextChangesUntil { return }
        // Cancel any background prefetch immediately — a live request always takes priority.
        prefetchTask?.cancel()
        // Task 7 — activation TTL: if a suggestion was shown very recently (~400ms), keep it
        // alive through spurious AX events by re-arming the debounce without clearing the overlay.
        if current != nil, Date().timeIntervalSince(shownAt) < 0.4 {
            debounce?.cancel()
            debounce = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                await self?.requestSuggestion()
            }
            return
        }
        // Adaptive debounce: a pause since the last change fires fast (~40ms) for an instant feel;
        // rapid changes wait longer (toward 200ms) so we don't burn inference on text about to change.
        let gapMs = Int(Date().timeIntervalSince(lastKeystrokeAt) * 1000)
        lastKeystrokeAt = Date()
        // Dim the overlay instead of clearing + hiding — prevents flicker during debounce.
        current = nil
        currentPID = 0
        currentContextKeys = []
        TabInterceptor.setSuggestionVisible(false)
        overlay.dim()
        debounce?.cancel()
        let ms = adaptive.nextDelayMs(sinceLastKeystrokeMs: gapMs)
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(ms))
            guard !Task.isCancelled else { return }
            await self?.requestSuggestion()
        }
    }

    private func requestImmediately() {
        guard isEnabled else { return }
        current = nil
        currentPID = 0
        currentContextKeys = []
        TabInterceptor.setSuggestionVisible(false)
        overlay.dim()
        debounce?.cancel()
        Task { await self.requestSuggestion() }
    }

    private func requestSuggestion() async {
        overlay.dim()                                   // dim (not hide) — prevents flicker during computation
        let gen = { self.suggestionGen += 1; return self.suggestionGen }()
        let t0 = Date()                                 // DIAG: measure where the per-keystroke latency goes

        // The Tab tap can only install once Accessibility is trusted. The user often grants it
        // AFTER launch, so the launch-time start() bailed. Retry here (idempotent): once we are
        // reading context successfully, AX is trusted, so the tap installs and — crucially — this
        // is where IOHIDRequestAccess fires to put Parrot in the Input Monitoring list.
        TabInterceptor.shared.start()

        // The target is the current frontmost app. `lastKnownFrontAppPID` is a cache updated only on
        // app-activation notifications, so it stays 0 from launch until the user's first app switch —
        // and Wren is a menu-bar accessory, so the user is normally ALREADY in their text app when it
        // launches (no activation fires). Fall back to the live frontmost app so completion works
        // immediately instead of silently bailing here on every keystroke.
        var pid = await AccessibilityBridge.shared.lastKnownFrontAppPID()
        if pid == 0 {
            pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        }
        guard pid != 0 else { return }
        let bundleID = await AppDetector.shared.frontAppBundleID(forPID: pid)
        if let id = bundleID, PreferencesStore.shared.isExcluded(bundleID: id) { return }
        let allowCode = await AppDetector.shared.isCodeEditor(bundleID: bundleID)

        // Per-app effective profile: resolves category defaults → rule overrides → global.
        let effectiveProfile: AppProfile = {
            guard let bundleID else { return .default }
            return PreferencesStore.shared.effectiveProfile(for: bundleID)
        }()
        let perAppMaxLength = effectiveProfile.maxCompletionLength
        let perAppScreenCtx = effectiveProfile.screenContextEnabled
        let perAppStyleInstructions = effectiveProfile.styleInstructions

        // Per-app completion rule: if an AppRule matches this bundleID and has a promptID,
        // use that custom prompt's template as the user prompt override.
        let appRulePrompt: String? = {
            guard let bundleID else { return nil }
            let rule = PreferencesStore.shared.appRules.first { $0.bundleID == bundleID && $0.isEnabled }
            guard let r = rule, let promptID = r.promptID else { return nil }
            return PreferencesStore.shared.customPrompts.first { $0.id == promptID }?.template
        }()
        // Reset per-app state when the focused application changes.
        if pid != lastBufferPID {
            typedBuffer.focusChanged()
            lastAXFoundField = false
            lastBufferPID = pid
        }

        let tPreAX = Date()
        let ax = await AccessibilityBridge.shared.completionContext(pid: pid)
        CrashLogger.log("DIAG timing: setup=\(Int(tPreAX.timeIntervalSince(t0)*1000))ms axRead=\(Int(Date().timeIntervalSince(tPreAX)*1000))ms")
        // Did AX just see a real, readable text field (valid caret & context)?
        let axHasField = ax?.caretRect != .zero && !(ax?.preContext.isEmpty ?? true)

        // Universal fallback when AX gives nothing readable — nil OR an empty value (Chromium web
        // fields, terminals often expose an empty AX value rather than nil). Complete from the
        // typed-input buffer, anchoring the ghost near the mouse cursor (floating hint).
        // AX-blind fallback DISABLED for now: fabricating a mouse-anchored ghost from the typed-input
        // buffer produced unreliable / nonsense suggestions outside real text fields (#5 — even "not in
        // a text box"). Wren suggests ONLY where AX exposes a real field. Proper AX-blind support for
        // Chromium/Electron is deferred to dedicated caret-bounds work.
        if ax == nil || (ax?.preContext.isEmpty ?? true) {
            #if DEBUG
            CrashLogger.log("DIAG req: AX empty → no suggestion (AX-blind fallback disabled)")
            #endif
            typedBuffer.invalidate()
            lastAXFoundField = false
            return
        }
        lastAXFoundField = axHasField
        guard let ax, !ax.isSecure else {
            #if DEBUG
            CrashLogger.log("DIAG req: ax=nil (no usable field)")
            #endif
            Logger.infra.debug("completion: no usable focused field (or secure)")
            return
        }
        #if DEBUG
        CrashLogger.log("DIAG req: app=\(bundleID ?? "?") preLen=\(ax.preContext.count) caret=\(ax.caretRect != .zero) allowCode=\(allowCode)")
        #endif

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
            guard suggestionGen == gen else { return }
            TabInterceptor.setSuggestionVisible(true)
            overlay.show(text: em.emoji, atCaretRect: ax.caretRect, fontName: ax.fontName, fontSize: ax.fontSize)
            await StatsStore.shared.recordShown()
            Logger.infra.debug("completion: emoji \(em.shortcode, privacy: .public) -> \(em.emoji, privacy: .public)")
            return
        }

        // Snippet expansion: type an abbreviation, Tab replaces it with the full expansion.
        // Checked before typo fix so intentional abbreviations aren't flagged as typos.
        if ax.caretRect != .zero, let snippet = SnippetMatcher.match(preContext: ax.preContext,
            snippets: PreferencesStore.shared.snippets) {
            current = CompletionSuggestion(text: snippet.expansion, kind: .replaceLastWord(wrong: snippet.abbreviation))
            currentPID = pid
            guard suggestionGen == gen else { return }
            TabInterceptor.setSuggestionVisible(true)
            overlay.show(text: snippet.expansion, atCaretRect: ax.caretRect, fontName: ax.fontName, fontSize: ax.fontSize)
            await StatsStore.shared.recordSnippetExpansion()
            Logger.infra.debug("completion: snippet \(snippet.abbreviation, privacy: .public) -> \(snippet.expansion, privacy: .public)")
            return
        }

        // Typo fix: if the just-typed word is misspelled, Tab corrects it (instead of completing).
        // Skipped in code editors (identifiers aren't typos). Cheap on-device spell check, no LLM.
        if !allowCode, ax.caretRect != .zero,
           let fix = TypoFix.check(preContext: ax.preContext, language: PreferencesStore.shared.language) {
            current = CompletionSuggestion(text: fix.correction, kind: .replaceLastWord(wrong: fix.wrong))
            currentPID = pid
            guard suggestionGen == gen else { return }
            TabInterceptor.setSuggestionVisible(true)
            overlay.show(text: "✓ " + fix.correction, atCaretRect: ax.caretRect, fontName: ax.fontName, fontSize: ax.fontSize)
            await StatsStore.shared.recordTypoFix()
            Logger.infra.debug("completion: typo fix \(fix.wrong, privacy: .public) -> \(fix.correction, privacy: .public)")
            return
        }

        // Learned (Cotypist-style, n-gram): if this context was completed before, suggest it INSTANTLY
        // — no model call → faster + personalized for your recurring phrases.
        let contextKeys = CompletionLearningStore.keys(forContext: ax.preContext)
        if !contextKeys.isEmpty,
           let learned = await CompletionLearningStore.shared.learnedSuggestion(keys: contextKeys),
           let cleaned = CompletionPostprocessor.clean(raw: learned.text, preContext: ax.preContext, maxWords: (perAppMaxLength ?? PreferencesStore.shared.maxCompletionLength) * 3, allowCode: allowCode) {
            current = CompletionSuggestion(text: cleaned, kind: .insert)
            currentPID = pid
            currentContextKeys = contextKeys
            await CompletionLearningStore.shared.noteShown(key: learned.key)
            guard suggestionGen == gen else { return }
            TabInterceptor.setSuggestionVisible(true)
            overlay.show(text: cleaned, atCaretRect: ax.caretRect, fontName: ax.fontName, fontSize: ax.fontSize)
            await StatsStore.shared.recordShown()
            Logger.infra.debug("completion: learned suggestion for '\(learned.key, privacy: .public)'")
            return
        }

        // Pre-model: cache and learning use the RAW typed text (ax.preContext), never enriched
        // context. Screen/OCR context includes previously-accepted completions, which would leak
        // the model's own output back into the cache/learning → feedback loop.
        let preContext = ax.preContext
        let cacheKey = String(preContext.suffix(80))

        // Cache gate: a context we have completed before returns instantly with no model call,
        // guaranteeing the sub-50ms hot path. Cleared implicitly as the LRU evicts.
        if ax.caretRect != .zero, let hit = cache.get(contextHash: cacheKey) {
            current = CompletionSuggestion(text: hit, kind: .insert)
            currentPID = pid
            currentContextKeys = contextKeys
            guard suggestionGen == gen else { return }
            TabInterceptor.setSuggestionVisible(true)
            overlay.show(text: hit, atCaretRect: ax.caretRect, fontName: ax.fontName, fontSize: ax.fontSize)
            shownAt = Date()
            await StatsStore.shared.recordShown()
            Logger.infra.debug("completion: cache hit")
            return
        }

        // Screen context: OCR of the conversation/email above the caret, prepended to the model
        // prompt ONLY (the cache key, learned keys, and typo-fix above all use the raw typed text).
        // Crop-above-caret excludes the input field, so the model never re-reads its own output.
        var modelPre = preContext
        let screenCtxEnabled = perAppScreenCtx ?? PreferencesStore.shared.completionScreenContextEnabled
        if !allowCode, ax.caretRect != .zero,
           screenCtxEnabled, ScreenContextProvider.hasPermission {
            let screenH = NSScreen.main?.frame.height ?? 0
            let screen = await ScreenContextProvider.shared.currentContext(pid: pid, caretRect: ax.caretRect, screenHeight: screenH)
            if !screen.isEmpty { modelPre = screen + "\n" + preContext }
        }

        // Merge per-app style instructions into the global personalization instructions.
        let globalInstructions = PreferencesStore.shared.personalizationInstructions
        let mergedInstructions: String = {
            if let perApp = perAppStyleInstructions, !perApp.isEmpty {
                if !globalInstructions.isEmpty { return globalInstructions + "\n\n" + perApp }
                return perApp
            }
            return globalInstructions
        }()
        let context = CompletionContext(preContext: modelPre, postContext: ax.postContext,
                                        language: PreferencesStore.shared.language,
                                        userPromptOverride: appRulePrompt,
                                        personalizationInstructions: mergedInstructions,
                                        personalizationStrength: PreferencesStore.shared.personalizationStrength,
                                        completionModelID: PreferencesStore.shared.completionModelID,
                                        selectedModelID: PreferencesStore.shared.selectedModelID)
        Logger.infra.debug("completion: preContext tail=…\(String(ax.preContext.suffix(40)), privacy: .public)")
        let maxWords = perAppMaxLength ?? PreferencesStore.shared.maxCompletionLength
        // Use the accurate (spell-check) mid-word detector here: a finished word like "ciao" (last
        // char a letter) must NOT be treated as mid-word, or it gets a phrase glued without a space.
        // The cheap isMidWordFast over-triggers on finished words; isMidWord disambiguates.
        let midWord = WordBoundary.isMidWord(preContext: preContext)
        // Mid-word: only finish the current word → ask for a short budget so generation is fast.
        let effectiveMaxWords = midWord ? 1 : maxWords
        #if DEBUG
        CrashLogger.log("DIAG req: calling engine, preTail=\(String(preContext.suffix(20))) midWord=\(midWord)")
        #endif
        let tPreEngine = Date()
        guard let suggestion = await CompletionEngine.shared.suggest(context: context, maxWords: effectiveMaxWords, allowCode: allowCode, midWord: midWord) else {
            CrashLogger.log("DIAG timing: engine=\(Int(Date().timeIntervalSince(tPreEngine)*1000))ms total=\(Int(Date().timeIntervalSince(t0)*1000))ms -> nil")
            Logger.infra.debug("completion: engine returned no suggestion")
            return
        }
        CrashLogger.log("DIAG timing: engine=\(Int(Date().timeIntervalSince(tPreEngine)*1000))ms total=\(Int(Date().timeIntervalSince(t0)*1000))ms suggestion='\(suggestion.text.prefix(30))'")
        guard !Task.isCancelled else { return }

        if ax.caretRect == .zero {
            Logger.infra.debug("completion: have suggestion but caret bounds .zero — app exposes no caret rect, cannot show ghost")
            return
        }

        guard suggestionGen == gen else { return }
        current = suggestion
        currentPID = pid
        currentContextKeys = contextKeys
        cache.set(contextHash: cacheKey, suggestion: suggestion.text)   // warm the hot path for repeats
        TabInterceptor.setSuggestionVisible(true)
        overlay.show(text: suggestion.text, atCaretRect: ax.caretRect, fontName: ax.fontName, fontSize: ax.fontSize)
        shownAt = Date()
        await StatsStore.shared.recordShown()
        Logger.infra.debug("completion: showing \(suggestion.text, privacy: .public) at \(NSStringFromRect(ax.caretRect), privacy: .public)")

        // NOTE: speculative accepted-branch pre-compute was tried here and REMOVED — the background
        // prefetch shares the single helper pipe and, with a 4B model, held it long enough that live
        // requests waited seconds (suggestions "disappeared, new only after seconds"). Cancelling the
        // Swift Task doesn't free the in-flight helper inference, so the contention stayed.
    }

    /// Tab — accept the suggestion: insert a completion, or fix a typo by replacing the last word.
    /// Returns true if a suggestion was actually consumed, false if already stale.
    @discardableResult
    func tryAcceptFull() -> Bool {
        guard let s = current, currentPID != 0 else { return false }
        // A FULL accept SHOULD let the next suggestion appear (served from the prefetch cache), so
        // clear any walk-suppression window left over from partial accepts.
        ignoreTextChangesUntil = .distantPast
        let pid = currentPID
        let text = s.text
        let kind = s.kind
        let keys = currentContextKeys
        clearSuggestion()
        Task {
            switch kind {
            case .insert:
                _ = await AccessibilityBridge.shared.insertCompletion(text, pid: pid)
                await StatsStore.shared.recordAccepted(text: text)
                if !keys.isEmpty { await CompletionLearningStore.shared.record(keys: keys, accepted: text) }
            case .replaceLastWord(let wrong):
                _ = await AccessibilityBridge.shared.replaceLastWord(wrong: wrong, with: text, pid: pid)
                await StatsStore.shared.recordAccepted(text: text)
            }
        }
        return true
    }

    /// Convenience wrapper for callers that don't need the return value.
    func acceptFull() { tryAcceptFull() }

    /// Partial accept — insert the first word only, then re-suggest from the new position.
    /// Only meaningful for completions; a typo fix has no "partial", so it accepts fully.
    /// Returns true if a suggestion was actually consumed, false if already stale.
    @discardableResult
    func tryAcceptPartial() -> Bool {
        guard let s = current, currentPID != 0 else { return false }
        guard case .insert = s.kind else { tryAcceptFull(); return true }
        let pid = currentPID
        let word = s.firstWord
        let remaining = String(s.text.dropFirst(word.count))
        let hasRemaining = !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Advance `current` to the remaining words SYNCHRONOUSLY. This makes rapid Tab predictable:
        // each press inserts the NEXT word of the SAME suggestion (never re-inserts this word, never
        // leaves a "no suggestion" gap where Tab would type a literal tab). We re-anchor the ghost at
        // the new caret WITHOUT a model call; only recompute once the suggestion is exhausted.
        if hasRemaining {
            current = CompletionSuggestion(text: remaining, kind: .insert)
            // Suppress the AX value-changed event our insert is about to cause, so textChanged() does
            // NOT regenerate and clobber the remaining words we're walking. Each Tab re-extends it.
            ignoreTextChangesUntil = Date().addingTimeInterval(0.6)
            // keep TabInterceptor visible flag TRUE so the next Tab is still captured
        } else {
            current = nil
            currentContextKeys = []
            TabInterceptor.setSuggestionVisible(false)
            overlay.hide()
        }
        Task {
            _ = await AccessibilityBridge.shared.insertCompletion(word, pid: pid)
            await StatsStore.shared.recordAccepted(text: word)
            if hasRemaining {
                let ax = await AccessibilityBridge.shared.completionContext(pid: pid)
                await MainActor.run {
                    guard self.current != nil else { return }   // typing superseded us meanwhile
                    if let ax, ax.caretRect != .zero {
                        self.overlay.show(text: remaining, atCaretRect: ax.caretRect)
                    } else {
                        self.overlay.hide()
                    }
                }
            } else {
                await MainActor.run { self.requestImmediately() }   // exhausted → fresh suggestion
            }
        }
        return true
    }

    /// Convenience wrapper for callers that don't need the return value.
    func acceptPartial() { tryAcceptPartial() }

    /// Clears any visible suggestion and cancels in-flight work.
    func dismiss() {
        debounce?.cancel()
        // Negative learning: increment show count for dismissed suggestions so their
        // acceptance rate drops — the user chose to keep typing instead of accepting.
        if !currentContextKeys.isEmpty {
            let keys = currentContextKeys
            Task {
                for k in keys { await CompletionLearningStore.shared.noteShown(key: k) }
            }
        }
        clearSuggestion()
        Task {
            await StatsStore.shared.recordDismissed()
            await CompletionEngine.shared.cancelPending()
        }
    }

    /// Dismiss when the user keeps typing (non-Tab key). Auto-corrects typo fixes on Space.
    func dismissForTyping(keycode: Int64) {
        debounce?.cancel()
        let s = current
        let pid = currentPID
        // Gboard-style auto-correct: Space accepts a typo fix without explicit Tab.
        if keycode == kVK_Space, let s, case .replaceLastWord(let wrong) = s.kind {
            clearSuggestion()
            Task {
                await StatsStore.shared.recordTypoFix()
                _ = await AccessibilityBridge.shared.replaceLastWord(wrong: wrong, with: s.text, pid: pid)
                await CompletionEngine.shared.cancelPending()
            }
            return
        }
        // All other keys: normal dismiss.
        if !currentContextKeys.isEmpty {
            let keys = currentContextKeys
            Task {
                for k in keys { await CompletionLearningStore.shared.noteShown(key: k) }
            }
        }
        clearSuggestion()
        Task {
            await StatsStore.shared.recordDismissed()
            await CompletionEngine.shared.cancelPending()
        }
    }

    private func clearSuggestion() {
        current = nil
        currentPID = 0
        currentContextKeys = []
        TabInterceptor.setSuggestionVisible(false)
        overlay.hide()
    }
}
