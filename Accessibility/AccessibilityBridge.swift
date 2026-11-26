import Cocoa
import OSLog

actor AccessibilityBridge: AXBridgeProtocol {
    static let shared = AccessibilityBridge()

    /// Upper bound for a single AX IPC round-trip. The system default is ~6 s, so one hung app
    /// would stall every AX call queued on this actor (Parrot hotkeys behind keystroke reads).
    nonisolated static let axMessagingTimeoutSeconds: Float = 0.5
    /// Max AX nodes visited by the `boundsForRange` subtree fallback (browser DOMs are huge).
    nonisolated static let maxSubtreeSearchNodes = 400
    /// Max UTF-16 units per synthetic Unicode key event; longer strings are truncated by macOS.
    nonisolated static let maxUnicodeUnitsPerKeyEvent = 20
    /// How long the corrected text stays on the clipboard before the user's clipboard is restored.
    /// Electron/Chromium apps read the pasteboard asynchronously and need much longer.
    nonisolated static let clipboardRestoreDelayNative: Duration = .milliseconds(200)
    nonisolated static let clipboardRestoreDelayElectron: Duration = .milliseconds(1000)

    /// Setting the messaging timeout on the system-wide element makes it the global default for
    /// every AX request this process sends. Runs once (static let initialisation is thread-safe).
    nonisolated private static let globalMessagingTimeoutInstalled: Bool = {
        let err = AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), axMessagingTimeoutSeconds)
        if err != .success {
            Logger.ax.error("AccessibilityBridge: AXUIElementSetMessagingTimeout failed (\(err.rawValue, privacy: .public))")
        }
        return err == .success
    }()

    /// Installs the global AX messaging timeout if not yet done. Safe to call from anywhere.
    nonisolated static func installAXMessagingTimeout() {
        _ = globalMessagingTimeoutInstalled
    }

    nonisolated private static func appElement(_ pid: pid_t) -> AXUIElement {
        installAXMessagingTimeout()
        let el = AXUIElementCreateApplication(pid)
        let err = AXUIElementSetMessagingTimeout(el, axMessagingTimeoutSeconds)
        if err != .success {
            Logger.ax.debug("AccessibilityBridge: per-app messaging timeout failed for pid \(pid) (\(err.rawValue, privacy: .public))")
        }
        return el
    }

    nonisolated private static func systemWideElement() -> AXUIElement {
        installAXMessagingTimeout()
        return AXUIElementCreateSystemWide()
    }

    init() {
        Self.removeLegacyClipboardStateFile()
    }

    nonisolated private static func asElement(_ ref: CFTypeRef) -> AXUIElement? {
        CFGetTypeID(ref) == AXUIElementGetTypeID() ? (ref as! AXUIElement) : nil // safe: CFGetTypeID checked
    }

    nonisolated private static func asAXValue(_ ref: CFTypeRef) -> AXValue? {
        CFGetTypeID(ref) == AXValueGetTypeID() ? (ref as! AXValue) : nil // safe: CFGetTypeID checked
    }

    nonisolated static func asElementPublic(_ ref: CFTypeRef?) -> AXUIElement? {
        guard let ref else { return nil }
        return CFGetTypeID(ref) == AXUIElementGetTypeID() ? (ref as! AXUIElement) : nil // safe: CFGetTypeID checked
    }

    private static let _boundsLock = OSAllocatedUnfairLock<CGRect>(initialState: .zero)

    nonisolated var lastSelectionBoundsSync: CGRect { Self._boundsLock.withLock { $0 } }

    private(set) var lastSelectionBounds: CGRect = .zero {
        didSet {
            let v = lastSelectionBounds
            Self._boundsLock.withLock { $0 = v }
        }
    }
    private var _lastKnownFrontAppPID: pid_t = 0
    /// PIDs we have already forced `AXManualAccessibility` on. Chromium/Electron apps expose no AX
    /// tree until a client sets this private attribute; once set it sticks for the process lifetime,
    /// so we only do it once per pid. Harmless no-op on native apps that ignore the attribute.
    private var manualAXEnabledPIDs: Set<pid_t> = []

    func setLastKnownFrontAppPID(_ pid: pid_t) {
        self._lastKnownFrontAppPID = pid
    }

    func lastKnownFrontAppPID() -> pid_t {
        return _lastKnownFrontAppPID
    }

    // Optional: nil means "no reliable range captured". Callers must NOT reuse a
    // stale value — a wrong range would overwrite the wrong span on apply.
    private(set) var lastSelectedRange: CFRange?

    func fetchTextOrLineAtCursor(fromPID pid: pid_t) async throws -> (text: String, range: CFRange?) {
        guard AXIsProcessTrusted() else {
            throw CorrectionError.accessibilityPermissionDenied
        }
        let frontAppAX = Self.appElement(pid)
        var focusedRef: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            frontAppAX, kAXFocusedUIElementAttribute as CFString, &focusedRef
        )
        guard focusResult == .success,
              let focusedElement = focusedRef,
              let element = Self.asElement(focusedElement) else {
            throw CorrectionError.noTextSelected
        }
        return try await fetchTextOrLineAtCursor(from: element)
    }

    func fetchTextOrLineAtCursor(from element: AXUIElement?) async throws -> (text: String, range: CFRange?) {
        guard let axElement = element else {
            throw CorrectionError.noTextSelected
        }
        var selectedTextRef: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(
            axElement, kAXSelectedTextAttribute as CFString, &selectedTextRef
        )
        if textResult == .success, let selectedText = selectedTextRef as? String, !selectedText.isEmpty {
            let range = await updateBounds(axElement: axElement)
            return (selectedText, range)
        }
        var rangeRef: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            axElement, kAXSelectedTextRangeAttribute as CFString, &rangeRef
        )
        var cursorRange = CFRange(location: 0, length: 0)
        if rangeResult == .success,
           let rangeValue = rangeRef,
           let axRange = Self.asAXValue(rangeValue) {
            AXValueGetValue(axRange, .cfRange, &cursorRange)
        }
        var valueRef: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            axElement, kAXValueAttribute as CFString, &valueRef
        )
        guard valueResult == .success,
              let fullText = valueRef as? String, !fullText.isEmpty else {
            throw CorrectionError.textExtractionFailed(appName: "unknown")
        }
        let nsText = fullText as NSString
        // Clamp: a stale AX cursor range past the end throws NSRangeException
        // in character(at:) below.
        let cursorPos = max(0, min(cursorRange.location, nsText.length))
        var lineStart = cursorPos
        while lineStart > 0 {
            let prev = nsText.character(at: lineStart - 1)
            if prev == UInt16(UnicodeScalar("\n").value) || prev == UInt16(UnicodeScalar("\r").value) { break }
            lineStart -= 1
        }
        var lineEnd = cursorPos
        while lineEnd < nsText.length {
            let ch = nsText.character(at: lineEnd)
            if ch == UInt16(UnicodeScalar("\n").value) || ch == UInt16(UnicodeScalar("\r").value) { break }
            lineEnd += 1
        }
        let lineRange = CFRange(location: lineStart, length: lineEnd - lineStart)
        let lineText = nsText.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart))
        guard !lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CorrectionError.textExtractionFailed(appName: "unknown")
        }
        self.lastSelectedRange = lineRange
        return (String(lineText), lineRange)
    }

    private func extractText(from axElement: AXUIElement) async throws -> (text: String, range: CFRange?) {
        var selectedTextRef: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(
            axElement, kAXSelectedTextAttribute as CFString, &selectedTextRef
        )
        if textResult == .success, let selectedText = selectedTextRef as? String, !selectedText.isEmpty {
            let range = await updateBounds(axElement: axElement)
            return (selectedText, range)
        }
        // No live selection. Signal the caller to fall back to line-at-cursor
        // extraction (fetchTextOrLineAtCursor), which captures the CFRange needed
        // for a targeted replace. Returning the whole kAXValue here would bypass
        // that path and duplicate the entire field on apply.
        throw CorrectionError.noTextSelected
    }

    func fetchSelectedText(fromPID pid: pid_t) async throws -> (text: String, range: CFRange?) {
        guard AXIsProcessTrusted() else {
            throw CorrectionError.accessibilityPermissionDenied
        }
        let frontAppAX = Self.appElement(pid)
        var focusedRef: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            frontAppAX, kAXFocusedUIElementAttribute as CFString, &focusedRef
        )
        guard focusResult == .success,
              let focusedElement = focusedRef,
              let element = Self.asElement(focusedElement) else {
            throw CorrectionError.noTextSelected
        }
        return try await extractText(from: element)
    }

    /// Full plain text of the focused element of `pid` (its kAXValueAttribute),
    /// or nil if unavailable. Used by Focus Mode's word counter — does not throw,
    /// does not prefer selected text.
    func focusedPlainText(pid: pid_t) async -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let appAX = Self.appElement(pid)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                appAX, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef,
              let element = Self.asElement(focused) else { return nil }
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                element, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String else { return nil }
        return value
    }

    func fetchSelectedText() async throws -> (text: String, range: CFRange?) {
        guard AXIsProcessTrusted() else {
            throw CorrectionError.accessibilityPermissionDenied
        }
        let systemAX = Self.systemWideElement()
        var frontAppRef: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(
            systemAX, kAXFocusedApplicationAttribute as CFString, &frontAppRef
        )
        guard appResult == .success,
              let frontApp = frontAppRef,
              let frontAppAX = Self.asElement(frontApp) else {
            throw CorrectionError.textExtractionFailed(appName: await AppDetector.shared.frontAppName(from: frontAppRef))
        }
        var focusedRef: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            frontAppAX, kAXFocusedUIElementAttribute as CFString, &focusedRef
        )
        guard focusResult == .success,
              let focusedElement = focusedRef,
              let element = Self.asElement(focusedElement) else {
            throw CorrectionError.noTextSelected
        }
        return try await extractText(from: element)
    }

    func replaceSelectedText(with correctedText: String) async throws {
        try await replaceSelectedText(with: correctedText, range: nil)
    }

    /// Replaces the selection (or the captured `range`) with `correctedText`.
    /// - Parameter expectedPID: when non-nil, the write is refused unless the
    ///   currently-focused app is still this PID — prevents overwriting a span in
    ///   a different document if focus moved during the LLM round-trip.
    /// - Parameter expectedText: the text the write is meant to replace (the original that was
    ///   corrected). When non-nil, the write is refused unless the focused field still holds it at
    ///   `range` (or as its live selection when `range` is nil) — prevents overwriting a different
    ///   document/field in the same app (tab switch, other field clicked) during the LLM round-trip.
    /// - Returns: the span actually written via a targeted AX replace, so undo can
    ///   re-select it exactly; nil if the write went through the clipboard or
    ///   replaced the live selection (span not known).
    @discardableResult
    func replaceSelectedText(
        with correctedText: String, range: CFRange?, expectedPID: pid_t? = nil, expectedText: String? = nil
    ) async throws -> CFRange? {
        guard AXIsProcessTrusted() else {
            throw CorrectionError.accessibilityPermissionDenied
        }
        // Chromium/Electron: AX setters claim success without touching DOM text.
        // Detect via last known PID and go directly to clipboard — but only if we
        // are still on the app the text was captured from.
        let targetPID = _lastKnownFrontAppPID
        if targetPID != 0, expectedPID == nil || targetPID == expectedPID {
            let bid = await AppDetector.shared.frontAppBundleID(forPID: targetPID)
            if let b = bid, await ElectronFallbackHandler.shared.isElectronApp(bundleID: b) {
                // Electron AX reads are unreliable, so only a positive mismatch blocks the paste.
                if let focused = Self.focusedElement(ofApp: Self.appElement(targetPID)) {
                    try verifyWriteTarget(focused, range: range, expectedText: expectedText, strict: false)
                }
                try await injectViaClipboard(correctedText: correctedText, targetPID: targetPID)
                return nil
            }
        }
        let systemAX = Self.systemWideElement()
        var frontAppRef: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(
            systemAX, kAXFocusedApplicationAttribute as CFString, &frontAppRef
        )
        guard appResult == .success,
              let frontApp = frontAppRef,
              let frontAppAX = Self.asElement(frontApp) else {
            throw CorrectionError.noTextSelected
        }
        // Fail closed if focus moved to a different app than the capture came from.
        if let expected = expectedPID {
            var focusedPID: pid_t = 0
            AXUIElementGetPid(frontAppAX, &focusedPID)
            guard focusedPID == expected else {
                throw CorrectionError.noTextSelected
            }
        }
        var focusedRef: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            frontAppAX, kAXFocusedUIElementAttribute as CFString, &focusedRef
        )
        guard focusResult == .success,
              let focusedElement = focusedRef,
              let axElement = Self.asElement(focusedElement) else {
            throw CorrectionError.noTextSelected
        }
        try verifyWriteTarget(axElement, range: range, expectedText: expectedText, strict: true)
        // If we captured a specific range at extraction time (the no-live-selection
        // path), re-select it first so the replace targets exactly that line/range
        // instead of inserting at the caret.
        if var r = range {
            guard let axRange = AXValueCreate(.cfRange, &r),
                  AXUIElementSetAttributeValue(
                    axElement, kAXSelectedTextRangeAttribute as CFString, axRange
                  ) == .success else {
                // Could not re-establish the selection. A paste only replaces text if the live
                // selection already IS the target; with a bare caret it would insert a duplicate.
                guard Self.liveSelectionIsTarget(axElement, length: r.length, expectedText: expectedText) else {
                    Logger.ax.warning("AccessibilityBridge: cannot re-select target range; refusing caret paste")
                    throw CorrectionError.noTextSelected
                }
                try await injectViaClipboard(correctedText: correctedText)
                return nil
            }
            // Replace the (now) selected range. Deliberately NO kAXValue fallback:
            // setting kAXValue overwrites the ENTIRE field, destroying surrounding
            // text when only a line/selection should change.
            let setResult = AXUIElementSetAttributeValue(
                axElement, kAXSelectedTextAttribute as CFString, correctedText as CFTypeRef
            )
            if setResult == .success {
                return CFRange(location: r.location, length: (correctedText as NSString).length)
            }
            try await injectViaClipboard(correctedText: correctedText)
            return nil
        }
        let setResult = AXUIElementSetAttributeValue(
            axElement, kAXSelectedTextAttribute as CFString, correctedText as CFTypeRef
        )
        if setResult == .success { return nil }
        try await injectViaClipboard(correctedText: correctedText)
        return nil
    }

    /// True when the element's live selection is the text a write targets (so pasting over it
    /// replaces exactly that). Matches `expectedText` when given, otherwise the target length.
    nonisolated private static func liveSelectionIsTarget(
        _ element: AXUIElement, length: CFIndex, expectedText: String?
    ) -> Bool {
        var selRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selRef) == .success,
              let selected = selRef as? String, !selected.isEmpty else { return false }
        return liveSelectionMatches(selected: selected, length: length, expectedText: expectedText)
    }

    nonisolated static func liveSelectionMatches(selected: String, length: CFIndex, expectedText: String?) -> Bool {
        guard !selected.isEmpty else { return false }
        if let expectedText { return checkSelectionTarget(selectedText: selected, expected: expectedText) == .match }
        return (selected as NSString).length == length
    }

    /// Result of checking that the focused field still holds the text a write is meant to replace.
    enum WriteTargetCheck: Equatable { case match, mismatch, unreadable }

    /// Pure check: does `fieldValue` hold `expected` at `range`? With `expected == nil` only the
    /// bounds are checked (a range past the end means a different/changed document).
    /// Whitespace at the edges is ignored because callers may hand over a trimmed original.
    nonisolated static func checkWriteTarget(fieldValue: String?, range: CFRange, expected: String?) -> WriteTargetCheck {
        guard let value = fieldValue else { return .unreadable }
        let ns = value as NSString
        guard range.location >= 0, range.length >= 0, range.location + range.length <= ns.length else {
            return .mismatch
        }
        guard let expected else { return .match }
        let actual = ns.substring(with: NSRange(location: range.location, length: range.length))
        return sameText(actual, expected) ? .match : .mismatch
    }

    /// Pure check for the live-selection path (no captured range).
    nonisolated static func checkSelectionTarget(selectedText: String?, expected: String?) -> WriteTargetCheck {
        guard let expected else { return .match }
        guard let selected = selectedText, !selected.isEmpty else { return .unreadable }
        return sameText(selected, expected) ? .match : .mismatch
    }

    nonisolated private static func sameText(_ a: String, _ b: String) -> Bool {
        a == b || a.trimmingCharacters(in: .whitespacesAndNewlines) == b.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func focusedElement(ofApp app: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let r = ref else { return nil }
        return asElement(r)
    }

    /// Fails closed (throws) when the focused field no longer holds the text the write targets.
    /// `strict`: an unreadable field also fails when an `expectedText` was given.
    private func verifyWriteTarget(_ element: AXUIElement, range: CFRange?, expectedText: String?, strict: Bool) throws {
        let check: WriteTargetCheck
        if let range {
            var valueRef: CFTypeRef?
            let read = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
            check = Self.checkWriteTarget(fieldValue: read == .success ? valueRef as? String : nil,
                                          range: range, expected: expectedText)
        } else {
            var selRef: CFTypeRef?
            let read = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selRef)
            check = Self.checkSelectionTarget(selectedText: read == .success ? selRef as? String : nil,
                                              expected: expectedText)
        }
        switch check {
        case .match:
            return
        case .mismatch:
            Logger.ax.warning("AccessibilityBridge: write refused — focused field no longer holds the original text")
            throw CorrectionError.noTextSelected
        case .unreadable:
            guard strict, expectedText != nil else { return }
            Logger.ax.warning("AccessibilityBridge: write refused — cannot verify the focused field's text")
            throw CorrectionError.noTextSelected
        }
    }

    private static let clipboardTokenType = NSPasteboard.PasteboardType("com.parrot.clipboard-token")

    /// Tail of the serialized clipboard-injection chain. Each injection waits for the previous one
    /// to finish (including its restore) so a second call never snapshots the first call's text as
    /// the user's "original" clipboard.
    private var clipboardInFlight: Task<Void, Never>?

    private func injectViaClipboard(correctedText: String, targetPID: pid_t = 0) async throws {
        let previous = clipboardInFlight
        let op = Task {
            await previous?.value
            try await self.performClipboardInjection(correctedText: correctedText, targetPID: targetPID)
        }
        clipboardInFlight = Task { _ = await op.result }
        try await op.value
    }

    nonisolated static func clipboardRestoreDelay(isElectron: Bool) -> Duration {
        isElectron ? clipboardRestoreDelayElectron : clipboardRestoreDelayNative
    }

    private func performClipboardInjection(correctedText: String, targetPID: pid_t) async throws {
        // NSPasteboard is not thread-safe — all reads/writes must happen on the main thread.
        let originalItems: [[String: Data]] = await MainActor.run {
            NSPasteboard.general.pasteboardItems?.compactMap { item -> [String: Data]? in
                var dict: [String: Data] = [:]
                for type in item.types {
                    if let data = item.data(forType: type) { dict[type.rawValue] = data }
                }
                return dict.isEmpty ? nil : dict
            } ?? []
        }

        let token = UUID().uuidString

        await MainActor.run {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(correctedText, forType: .string)
            pb.setString(token, forType: Self.clipboardTokenType)
        }

        // Re-activate the target app so Cmd+V lands in the right window.
        // This is required for Electron apps (WhatsApp, Teams, etc.) where clicking
        // the suggestion panel may have shifted the first-responder.
        let pid = targetPID != 0 ? targetPID : _lastKnownFrontAppPID
        if pid != 0 {
            await MainActor.run {
                _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [])
            }
            // Poll until the app actually becomes active (up to 500ms) instead of
            // a fixed 80ms sleep — fast apps respond quickly, slow ones get more time.
            let deadline = Date().addingTimeInterval(0.5)
            var becameActive = false
            while Date() < deadline {
                if NSRunningApplication(processIdentifier: pid)?.isActive == true {
                    becameActive = true
                    break
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            if !becameActive {
                // The app didn't become active in time — the Cmd+V that follows
                // may land elsewhere. This is rare but logged for diagnostics.
                Logger.ax.warning("AccessibilityBridge: target app (pid \(pid)) did not activate within 500ms")
            }
        }

        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x09), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x09), keyDown: false) else {
            await restoreClipboard(PendingClipboardRestore(items: originalItems))
            Logger.ax.error("AccessibilityBridge: could not create Cmd+V events — paste not performed")
            throw CorrectionError.textExtractionFailed(appName: "unknown")
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        let bundleID = pid != 0 ? await AppDetector.shared.frontAppBundleID(forPID: pid) : nil
        let isElectron: Bool
        if let b = bundleID {
            isElectron = await ElectronFallbackHandler.shared.isElectronApp(bundleID: b)
        } else {
            isElectron = false
        }
        // Not `try`: a cancellation here must still restore the user's clipboard below.
        do {
            try await Task.sleep(for: Self.clipboardRestoreDelay(isElectron: isElectron))
        } catch {
            Logger.ax.debug("AccessibilityBridge: clipboard restore wait cancelled — restoring now")
        }

        // Restore only if the clipboard still holds OUR text: if the user copied something in the
        // meantime, that newer content wins. An empty original clipboard is restored as empty, so
        // the corrected text is not left behind.
        let existingToken = await MainActor.run { NSPasteboard.general.string(forType: Self.clipboardTokenType) }
        if existingToken == token {
            await restoreClipboard(PendingClipboardRestore(items: originalItems))
        } else {
            Logger.ax.debug("AccessibilityBridge: clipboard changed during paste — not restoring")
        }
    }

    private func restoreClipboard(_ pending: PendingClipboardRestore) async {
        await MainActor.run {
            let pb = NSPasteboard.general
            pb.clearContents()
            let items = pending.pasteboardItems()
            if !items.isEmpty { pb.writeObjects(items) }
        }
    }

    func frontAppBundleID() async -> String? {
        await AppDetector.shared.frontAppBundleID()
    }

    func fetchRichText(on axElement: AXUIElement, plainText: String) -> RichTextContext {
        var attrRef: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            axElement,
            kAXAttributedStringForRangeParameterizedAttribute as CFString,
            CFRange(location: 0, length: plainText.utf16.count) as CFTypeRef,
            &attrRef
        )
        if result == .success, let attr = attrRef as? NSAttributedString {
            return RichTextContext(plainText: plainText, attributedString: attr)
        }
        return RichTextContext(plainText: plainText, attributedString: nil)
    }

    // MARK: - Focused element helper

    nonisolated func withFocusedElement<T>(pid: pid_t? = nil, _ body: (AXUIElement) async throws -> T) async throws -> T {
        guard AXIsProcessTrusted() else { throw CorrectionError.accessibilityPermissionDenied }
        let appElement: AXUIElement
        if let pid {
            appElement = Self.appElement(pid)
        } else {
            let systemAX = Self.systemWideElement()
            var frontAppRef: CFTypeRef?
            let appResult = AXUIElementCopyAttributeValue(
                systemAX, kAXFocusedApplicationAttribute as CFString, &frontAppRef
            )
            guard appResult == .success,
                  let frontApp = frontAppRef,
                  let app = Self.asElement(frontApp) else {
                throw CorrectionError.textExtractionFailed(appName: "unknown")
            }
            appElement = app
        }
        var focusedRef: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef
        )
        guard focusResult == .success,
              let focusedElement = focusedRef,
              let element = Self.asElement(focusedElement) else {
            throw CorrectionError.noTextSelected
        }
        return try await body(element)
    }

    // MARK: - Public AX utilities

    // MARK: - Inline completion (SP1)

    /// Reads the focused field's text split at the caret, the caret screen rect, and whether the
    /// field is a secure (password) field. Returns nil if nothing usable is focused.
    func completionContext(pid: pid_t) async -> CompletionAXContext? {
        guard AXIsProcessTrusted() else { return nil }
        let appAX = Self.appElement(pid)

        if let ctx = readCompletionContext(appAX: appAX) { return ctx }

        // Blind read. If we have not yet forced the AX tree on for this process, do it once and
        // retry — this is what makes Chromium/Electron apps (Slack, VSCode, browsers) readable.
        // Setting the attribute on a native app that ignores it is harmless.
        if !manualAXEnabledPIDs.contains(pid) {
            manualAXEnabledPIDs.insert(pid)
            AXUIElementSetAttributeValue(appAX, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            return readCompletionContext(appAX: appAX)   // may still be nil this tick; sticks for next
        }
        return nil
    }

    /// One synchronous attempt to read the focused field's split context + caret rect. Returns nil
    /// if nothing usable is focused (or the AX tree is not yet exposed).
    private func readCompletionContext(appAX: AXUIElement) -> CompletionAXContext? {
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appAX, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef, let element = Self.asElement(focused) else { return nil }

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
        // No public constant for the secure-field role; match the AX string ("AXSecureTextField").
        let isSecure = (roleRef as? String) == "AXSecureTextField"
            || (subroleRef as? String) == "AXSecureTextField"

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rv = rangeRef, let axRange = Self.asAXValue(rv) else { return nil }
        var caretRange = CFRange(location: 0, length: 0)
        AXValueGetValue(axRange, .cfRange, &caretRange)
        // Only complete at a collapsed caret — never when a selection exists.
        guard caretRange.length == 0 else { return nil }

        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let fullText = valueRef as? String else { return nil }
        let ns = fullText as NSString
        let caret = max(0, min(caretRange.location, ns.length))
        let pre = ns.substring(to: caret)
        let post = ns.substring(from: caret)

        let probe = caret > 0 ? CFRange(location: caret - 1, length: 1) : CFRange(location: 0, length: 1)
        let rect = axBoundsForRange(probe, on: element) ?? .zero

        var fName: String? = nil
        var fSize: CGFloat = 0
        var fontRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXFont" as CFString, &fontRef) == .success,
           let dict = fontRef as? [String: Any] {
            fName = dict["AXFontName"] as? String
            fSize = (dict["AXFontSize"] as? CGFloat) ?? 0
        }

        return CompletionAXContext(preContext: pre, postContext: post, caretRect: rect, isSecure: isSecure,
                                   fontName: fName, fontSize: fSize)
    }

    /// Fixes a typo: deletes the mistyped last word (backspaces) then types the correction.
    /// Synthesized keystrokes work across AppKit/Electron/web/terminal.
    func replaceLastWord(wrong: String, with correction: String, pid: pid_t) async -> Bool {
        guard !wrong.isEmpty else { return await insertCompletion(correction, pid: pid) }
        // Abort if the field's trailing text is no longer `wrong` (user edited since we matched) — we
        // must never blind-delete characters we haven't verified. Only enforced when AX can read it.
        if let ctx = readCompletionContext(appAX: Self.appElement(pid)),
           !ctx.preContext.hasSuffix(wrong) {
            Logger.ax.debug("replaceLastWord: trailing word changed, aborting")
            return false
        }
        guard await isFrontmost(pid: pid) else { return false }
        let source = CGEventSource(stateID: .combinedSessionState)
        let kVKDelete: CGKeyCode = 51
        for _ in 0..<wrong.count {
            Self.postWithoutModifiers(CGEvent(keyboardEventSource: source, virtualKey: kVKDelete, keyDown: true))
            Self.postWithoutModifiers(CGEvent(keyboardEventSource: source, virtualKey: kVKDelete, keyDown: false))
        }
        return await insertCompletion(correction, pid: pid)
    }

    /// Inserts completion text at the caret by synthesizing typing (a Unicode keyboard event).
    /// This is the most universal method — it works in AppKit, Electron, web fields, terminals —
    /// where AX value-setting silently fails. Returns false if `pid` is no longer frontmost (the
    /// keystrokes would land in another app) or if event creation fails.
    func insertCompletion(_ text: String, pid: pid_t) async -> Bool {
        guard !text.isEmpty else { return false }
        guard await isFrontmost(pid: pid) else { return false }
        let source = CGEventSource(stateID: .combinedSessionState)
        for chunk in Self.unicodeChunks(text, maxUnits: Self.maxUnicodeUnitsPerKeyEvent) {
            var units = chunk
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                Logger.ax.error("insertCompletion: could not create keyboard events")
                return false
            }
            keyDown.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            keyUp.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            Self.postWithoutModifiers(keyDown)
            Self.postWithoutModifiers(keyUp)
        }
        Logger.ax.debug("insertCompletion: typed \(text.count, privacy: .public) chars")
        return true
    }

    /// Synthetic events otherwise inherit physically-held modifiers (e.g. ⌥⇧ still down from the
    /// backslash accept on an Italian layout), turning typed text into shortcuts / ⌥⌫ word deletes.
    nonisolated private static func postWithoutModifiers(_ event: CGEvent?) {
        guard let event else { return }
        event.flags = []
        event.post(tap: .cghidEventTap)
    }

    private func isFrontmost(pid: pid_t) async -> Bool {
        let front = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        guard Self.isTargetFrontmost(frontPID: front, target: pid) else {
            Logger.ax.debug("synthetic typing skipped: pid \(pid) is not frontmost")
            return false
        }
        return true
    }

    nonisolated static func isTargetFrontmost(frontPID: pid_t?, target: pid_t) -> Bool {
        target != 0 && frontPID == target
    }

    /// Splits `text` into UTF-16 chunks of at most `maxUnits`, never splitting a grapheme cluster
    /// when it fits, and never splitting a surrogate pair (an oversize cluster is split by scalar).
    nonisolated static func unicodeChunks(_ text: String, maxUnits: Int) -> [[UInt16]] {
        let limit = max(maxUnits, 2)   // a surrogate pair needs 2 units
        var chunks: [[UInt16]] = []
        var current: [UInt16] = []
        func append(_ units: [UInt16]) {
            if current.count + units.count > limit, !current.isEmpty {
                chunks.append(current)
                current = []
            }
            current += units
        }
        for ch in text {
            let units = Array(String(ch).utf16)
            if units.count <= limit {
                append(units)
            } else {
                for scalar in ch.unicodeScalars { append(Array(String(scalar).utf16)) }
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    func boundsForRange(_ range: CFRange, pid: pid_t) async -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let appAX = Self.appElement(pid)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appAX, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef, let element = Self.asElement(focused) else { return nil }

        if let rect = axBoundsForRange(range, on: element) { return rect }

        // Tree-traversal fallback: walk AX subtree to find an element that exposes bounds.
        // Disabled per-app via PreferencesStore.treeTraversalDisabledBundleIDs.
        let bundleID = await AppDetector.shared.frontAppBundleID(forPID: pid)
        let traversalDisabled = await MainActor.run {
            bundleID.map { PreferencesStore.shared.isTreeTraversalDisabled(bundleID: $0) } ?? false
        }
        guard !traversalDisabled else { return nil }
        var budget = Self.maxSubtreeSearchNodes
        return axSearchSubtree(of: element, range: range, depth: 0, maxDepth: 8, budget: &budget)
    }

    private func axBoundsForRange(_ range: CFRange, on element: AXUIElement) -> CGRect? {
        var cfRange = range
        guard let axRangeValue = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, axRangeValue, &boundsRef
        ) == .success,
        let bv = boundsRef, let axBV = Self.asAXValue(bv) else { return nil }
        var rect = CGRect()
        AXValueGetValue(axBV, .cgRect, &rect)
        guard rect != .zero else { return nil }
        // AX origin is the top-left of the PRIMARY screen (screens[0]), not of NSScreen.main (the
        // screen with the key window) — using main offsets the caret on multi-monitor setups.
        return Self.flipAXRectToAppKit(rect, primaryScreenHeight: NSScreen.screens.first?.frame.height ?? 0)
    }

    /// Converts an AX (top-left origin, y down) rect to AppKit (bottom-left origin, y up).
    nonisolated static func flipAXRectToAppKit(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.origin.x, y: primaryScreenHeight - rect.origin.y - rect.height,
               width: rect.width, height: rect.height)
    }

    // DFS through AX children. Skips subtrees with >300 children to avoid browser DOM spam, and
    // stops after `budget` nodes in total (each node costs several AX IPC round-trips).
    private func axSearchSubtree(of element: AXUIElement, range: CFRange, depth: Int, maxDepth: Int,
                                 budget: inout Int) -> CGRect? {
        guard depth < maxDepth, budget > 0 else { return nil }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let ref = childrenRef,
              CFGetTypeID(ref) == CFArrayGetTypeID() else { return nil }
        let arr = ref as! CFArray // safe: CFGetTypeID checked above
        let count = CFArrayGetCount(arr)
        guard count > 0 && count < 300 else { return nil }
        for i in 0..<count {
            guard budget > 0 else { return nil }
            guard let raw = CFArrayGetValueAtIndex(arr, i) else { continue }
            budget -= 1
            let child = Unmanaged<AXUIElement>.fromOpaque(raw).retain().takeRetainedValue()
            if let rect = axBoundsForRange(range, on: child) { return rect }
            if let rect = axSearchSubtree(of: child, range: range, depth: depth + 1, maxDepth: maxDepth,
                                          budget: &budget) { return rect }
        }
        return nil
    }

    func fetchSurroundingText(pid: pid_t, selectionRange: CFRange, windowSize: Int = 600) async -> String {
        guard AXIsProcessTrusted() else { return "" }
        let appAX = Self.appElement(pid)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appAX, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success,
              let focused = focusedRef, let element = Self.asElement(focused) else { return "" }

        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let fullText = valueRef as? String, !fullText.isEmpty else { return "" }

        let nsText = fullText as NSString
        let selStart = max(0, min(selectionRange.location, nsText.length))
        let selEnd   = min(nsText.length, selStart + max(selectionRange.length, 0))
        let ctxStart = max(0, selStart - windowSize)
        let ctxEnd   = min(nsText.length, selEnd + 200)
        guard ctxEnd > ctxStart else { return "" }
        return nsText.substring(with: NSRange(location: ctxStart, length: ctxEnd - ctxStart))
    }

    /// Replaces `range` in the focused field of `pid` with `text`.
    /// - Parameter expectedText: the original text at `range` (e.g. the annotation's snippet). When
    ///   non-nil the write is refused unless the field still holds it there; the range is always
    ///   bounds-checked against the current value when the value is readable.
    func replaceRange(_ range: CFRange, with text: String, pid: pid_t, expectedText: String? = nil) async throws {
        guard AXIsProcessTrusted() else { throw CorrectionError.accessibilityPermissionDenied }
        let appAX = Self.appElement(pid)
        guard let element = Self.focusedElement(ofApp: appAX) else {
            throw CorrectionError.noTextSelected
        }
        try verifyWriteTarget(element, range: range, expectedText: expectedText, strict: true)
        var cfRange = range
        guard let axRangeValue = AXValueCreate(.cfRange, &cfRange) else { throw CorrectionError.noTextSelected }
        // If the range cannot be selected, nothing has been written yet: stop here. Writing
        // kAXSelectedText or pasting now would insert at the caret instead of replacing the span.
        let selectResult = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRangeValue)
        guard selectResult == .success else {
            Logger.ax.warning("replaceRange: could not select target range (\(selectResult.rawValue, privacy: .public))")
            throw CorrectionError.noTextSelected
        }
        // The span is selected: if the AX write fails, a paste replaces exactly that selection.
        let setResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        if setResult != .success {
            try await injectViaClipboard(correctedText: text, targetPID: pid)
        }
    }

    // MARK: - Private Helpers

    @discardableResult
    private func updateBounds(axElement: AXUIElement) async -> CFRange? {
        var capturedRange: CFRange?
        // Reset first so a failed range read yields nil, never a stale prior value.
        self.lastSelectedRange = nil
        var rangeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(
            axElement, kAXSelectedTextRangeAttribute as CFString, &rangeRef
        )

        if let rangeValue = rangeRef,
           let axRange = Self.asAXValue(rangeValue) {
            var cfRange = CFRange()
            AXValueGetValue(axRange, .cfRange, &cfRange)
            self.lastSelectedRange = cfRange
            capturedRange = cfRange

            var boundsRef: CFTypeRef?
            let boundsResult = AXUIElementCopyParameterizedAttributeValue(
                axElement,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                rangeValue,
                &boundsRef
            )

            if boundsResult == .success,
               let boundsValue = boundsRef,
               let axValue = Self.asAXValue(boundsValue) {
                var rect = CGRect()
                AXValueGetValue(axValue, .cgRect, &rect)
                self.lastSelectionBounds = rect
                return capturedRange
            }
        }

        let systemAX = Self.systemWideElement()
        var frontAppRef: CFTypeRef?
        AXUIElementCopyAttributeValue(systemAX, kAXFocusedApplicationAttribute as CFString, &frontAppRef)
        if let app = frontAppRef, let axApp = Self.asElement(app) {
            var frontWindowRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &frontWindowRef)
            if let window = frontWindowRef, let axWindow = Self.asElement(window) {
                var pos: CFTypeRef?
                var size: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &pos)
                AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &size)

                if let p = pos, let s = size,
                   let axPos = Self.asAXValue(p), let axSize = Self.asAXValue(s) {
                    var point = CGPoint()
                    var sz = CGSize()
                    AXValueGetValue(axPos, .cgPoint, &point)
                    AXValueGetValue(axSize, .cgSize, &sz)
                    self.lastSelectionBounds = CGRect(origin: point, size: sz)
                    return capturedRange
                }
            }
        }

        // No anchor (neither selection nor window bounds readable): .zero means "follow the mouse".
        // Never store an AppKit-space screen frame here — every reader treats this as an AX rect.
        self.lastSelectionBounds = .zero
        return capturedRange
    }
}

// MARK: - Clipboard Restore

/// Snapshot of the pasteboard captured before Parrot overwrites it.
/// Stored as a Sendable `[type: data]` representation (not `NSPasteboardItem`,
/// which is non-Sendable) so it can cross actor boundaries safely.
struct PendingClipboardRestore: Sendable {
    let items: [[String: Data]]

    /// Where older builds persisted the clipboard snapshot as plaintext JSON. Clipboard contents
    /// are no longer written to disk; the file is only located so it can be deleted.
    static var legacyStateFileURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let parrotDir = dir.appendingPathComponent("Parrot")
        return parrotDir.appendingPathComponent("clipboard_state.json")
    }

    /// Reconstructs `NSPasteboardItem`s from the snapshot. Call on the main thread.
    func pasteboardItems() -> [NSPasteboardItem] {
        items.compactMap { dict -> NSPasteboardItem? in
            let item = NSPasteboardItem()
            for (typeRaw, data) in dict {
                item.setData(data, forType: NSPasteboard.PasteboardType(rawValue: typeRaw))
            }
            return item.types.isEmpty ? nil : item
        }
    }
}

extension AccessibilityBridge {
    /// Deletes the plaintext clipboard snapshot older builds left in Caches. Idempotent.
    nonisolated static func removeLegacyClipboardStateFile(at url: URL = PendingClipboardRestore.legacyStateFileURL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Logger.ax.error("AccessibilityBridge: could not delete legacy clipboard snapshot — \(error.localizedDescription, privacy: .public)")
        }
    }
}
