import Cocoa
import OSLog

actor AccessibilityBridge: AXBridgeProtocol {
    static let shared = AccessibilityBridge()

    nonisolated private static func asElement(_ ref: CFTypeRef) -> AXUIElement? {
        CFGetTypeID(ref) == AXUIElementGetTypeID() ? (ref as! AXUIElement) : nil
    }

    nonisolated private static func asAXValue(_ ref: CFTypeRef) -> AXValue? {
        CFGetTypeID(ref) == AXValueGetTypeID() ? (ref as! AXValue) : nil
    }

    nonisolated static func asElementPublic(_ ref: CFTypeRef?) -> AXUIElement? {
        guard let ref else { return nil }
        return CFGetTypeID(ref) == AXUIElementGetTypeID() ? (ref as! AXUIElement) : nil
    }

    private static let _boundsLock = OSAllocatedUnfairLock<CGRect>(initialState: .zero)

    nonisolated var lastSelectionBoundsSync: CGRect { Self._boundsLock.withLock { $0 } }

    private(set) var lastSelectionBounds: CGRect = .zero {
        didSet {
            let v = lastSelectionBounds
            Self._boundsLock.withLock { $0 = v }
        }
    }
    private var pendingClipboardRestore: PendingClipboardRestore?
    private var _lastKnownFrontAppPID: pid_t = 0

    func setLastKnownFrontAppPID(_ pid: pid_t) {
        self._lastKnownFrontAppPID = pid
    }

    func lastKnownFrontAppPID() -> pid_t {
        return _lastKnownFrontAppPID
    }

    private(set) var lastSelectedRange: CFRange = CFRange(location: 0, length: 0)

    func fetchTextOrLineAtCursor(fromPID pid: pid_t) async throws -> (text: String, range: CFRange) {
        guard AXIsProcessTrusted() else {
            throw CorrectionError.accessibilityPermissionDenied
        }
        let frontAppAX = AXUIElementCreateApplication(pid)
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

    func fetchTextOrLineAtCursor(from element: AXUIElement?) async throws -> (text: String, range: CFRange) {
        guard let axElement = element else {
            throw CorrectionError.noTextSelected
        }
        var selectedTextRef: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(
            axElement, kAXSelectedTextAttribute as CFString, &selectedTextRef
        )
        if textResult == .success, let selectedText = selectedTextRef as? String, !selectedText.isEmpty {
            await updateBounds(axElement: axElement)
            return (selectedText, lastSelectedRange)
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
        let cursorPos = cursorRange.location
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

    private func extractText(from axElement: AXUIElement) async throws -> String {
        var selectedTextRef: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(
            axElement, kAXSelectedTextAttribute as CFString, &selectedTextRef
        )
        if textResult == .success, let selectedText = selectedTextRef as? String, !selectedText.isEmpty {
            await updateBounds(axElement: axElement)
            return selectedText
        }
        var valueRef: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            axElement, kAXValueAttribute as CFString, &valueRef
        )
        if valueResult == .success, let val = valueRef as? String, !val.isEmpty {
            await updateBounds(axElement: axElement)
            return val
        }
        throw CorrectionError.textExtractionFailed(appName: "unknown")
    }

    func fetchSelectedText(fromPID pid: pid_t) async throws -> String {
        guard AXIsProcessTrusted() else {
            throw CorrectionError.accessibilityPermissionDenied
        }
        let frontAppAX = AXUIElementCreateApplication(pid)
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

    func fetchSelectedText() async throws -> String {
        guard AXIsProcessTrusted() else {
            throw CorrectionError.accessibilityPermissionDenied
        }
        let systemAX = AXUIElementCreateSystemWide()
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
        guard AXIsProcessTrusted() else {
            throw CorrectionError.accessibilityPermissionDenied
        }
        // Chromium/Electron: AX setters claim success without touching DOM text.
        // Detect via last known PID and go directly to clipboard.
        let targetPID = _lastKnownFrontAppPID
        let hasSelection = lastSelectedRange.length > 0
        if targetPID != 0 {
            let bid = await AppDetector.shared.frontAppBundleID(forPID: targetPID)
            if let b = bid, await ElectronFallbackHandler.shared.isElectronApp(bundleID: b) {
                try await injectViaClipboard(correctedText: correctedText, targetPID: targetPID,
                                             selectAllFirst: !hasSelection)
                return
            }
        }
        let systemAX = AXUIElementCreateSystemWide()
        var frontAppRef: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(
            systemAX, kAXFocusedApplicationAttribute as CFString, &frontAppRef
        )
        guard appResult == .success,
              let frontApp = frontAppRef,
              let frontAppAX = Self.asElement(frontApp) else {
            throw CorrectionError.noTextSelected
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
        if hasSelection {
            // Re-select the known range then replace, avoiding stale-cursor drift.
            var mutableRange = lastSelectedRange
            if let axRangeValue = AXValueCreate(.cfRange, &mutableRange) {
                AXUIElementSetAttributeValue(
                    axElement, kAXSelectedTextRangeAttribute as CFString, axRangeValue)
            }
            let setResult = AXUIElementSetAttributeValue(
                axElement, kAXSelectedTextAttribute as CFString, correctedText as CFTypeRef
            )
            if setResult == .success { return }
        }
        // No selection (or setSelectedText failed): replace entire field value.
        // kAXSelectedTextAttribute with empty selection inserts at cursor — skip it.
        let valueResult = AXUIElementSetAttributeValue(
            axElement, kAXValueAttribute as CFString, correctedText as CFTypeRef
        )
        if valueResult == .success { return }
        try await injectViaClipboard(correctedText: correctedText, selectAllFirst: !hasSelection)
    }

    private static let clipboardTokenType = NSPasteboard.PasteboardType("com.parrot.clipboard-token")

    private func injectViaClipboard(correctedText: String, targetPID: pid_t = 0, selectAllFirst: Bool = false) async throws {
        // NSPasteboard is not thread-safe — all reads/writes must happen on the main thread.
        let originalItems: [NSPasteboardItem] = await MainActor.run {
            NSPasteboard.general.pasteboardItems?.compactMap { item in
                let copy = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) { copy.setData(data, forType: type) }
                }
                return copy
            } ?? []
        }

        if let existing = self.pendingClipboardRestore {
            await restoreClipboard(existing)
            self.pendingClipboardRestore = nil
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
                NSRunningApplication(processIdentifier: pid)?.activate(options: [])
            }
            // Wait for the app to become key before we post the keystroke.
            try await Task.sleep(for: .milliseconds(80))
        }

        let source = CGEventSource(stateID: .hidSystemState)
        // When no text was selected, send Cmd+A first to select all before pasting.
        if selectAllFirst {
            let aKeyCode: CGKeyCode = 0x00
            if let selDown = CGEvent(keyboardEventSource: source, virtualKey: aKeyCode, keyDown: true),
               let selUp   = CGEvent(keyboardEventSource: source, virtualKey: aKeyCode, keyDown: false) {
                selDown.flags = .maskCommand
                selUp.flags   = .maskCommand
                selDown.post(tap: .cghidEventTap)
                selUp.post(tap: .cghidEventTap)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        let vKeyCode: CGKeyCode = 0x09
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            if !originalItems.isEmpty {
                await restoreClipboard(PendingClipboardRestore(items: originalItems))
            }
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        guard !originalItems.isEmpty else { return }

        try await Task.sleep(for: .milliseconds(200))

        let existingToken = await MainActor.run { NSPasteboard.general.string(forType: Self.clipboardTokenType) }
        if existingToken == token {
            await restoreClipboard(PendingClipboardRestore(items: originalItems))
        } else {
            let pending = PendingClipboardRestore(items: originalItems)
            pending.persistToDisk()
            self.pendingClipboardRestore = pending
        }
    }

    private func restoreClipboard(_ pending: PendingClipboardRestore) async {
        await MainActor.run {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects(pending.items)
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
            appElement = AXUIElementCreateApplication(pid)
        } else {
            let systemAX = AXUIElementCreateSystemWide()
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

    func boundsForRange(_ range: CFRange, pid: pid_t) async -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let appAX = AXUIElementCreateApplication(pid)
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
        return axSearchSubtree(of: element, range: range, depth: 0, maxDepth: 8)
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
        let screenH = NSScreen.main?.frame.height ?? 0
        return CGRect(x: rect.origin.x, y: screenH - rect.origin.y - rect.height,
                      width: rect.width, height: rect.height)
    }

    // DFS through AX children. Skips subtrees with >300 children to avoid browser DOM spam.
    private func axSearchSubtree(of element: AXUIElement, range: CFRange, depth: Int, maxDepth: Int) -> CGRect? {
        guard depth < maxDepth else { return nil }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let ref = childrenRef,
              CFGetTypeID(ref) == CFArrayGetTypeID() else { return nil }
        let arr = ref as! CFArray
        let count = CFArrayGetCount(arr)
        guard count > 0 && count < 300 else { return nil }
        for i in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(arr, i) else { continue }
            let child = Unmanaged<AXUIElement>.fromOpaque(raw).retain().takeRetainedValue()
            if let rect = axBoundsForRange(range, on: child) { return rect }
            if let rect = axSearchSubtree(of: child, range: range, depth: depth + 1, maxDepth: maxDepth) { return rect }
        }
        return nil
    }

    func fetchSurroundingText(pid: pid_t, selectionRange: CFRange, windowSize: Int = 600) async -> String {
        guard AXIsProcessTrusted() else { return "" }
        let appAX = AXUIElementCreateApplication(pid)
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

    func replaceRange(_ range: CFRange, with text: String, pid: pid_t) async throws {
        guard AXIsProcessTrusted() else { throw CorrectionError.accessibilityPermissionDenied }
        let appAX = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appAX, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef, let element = Self.asElement(focused) else {
            throw CorrectionError.noTextSelected
        }
        var cfRange = range
        guard let axRangeValue = AXValueCreate(.cfRange, &cfRange) else { throw CorrectionError.noTextSelected }
        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRangeValue)
        AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
    }

    // MARK: - Private Helpers

    private func updateBounds(axElement: AXUIElement) async {
        var rangeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(
            axElement, kAXSelectedTextRangeAttribute as CFString, &rangeRef
        )

        if let rangeValue = rangeRef,
           let axRange = Self.asAXValue(rangeValue) {
            var cfRange = CFRange()
            AXValueGetValue(axRange, .cfRange, &cfRange)
            self.lastSelectedRange = cfRange

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
                return
            }
        }

        let systemAX = AXUIElementCreateSystemWide()
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
                    return
                }
            }
        }

        self.lastSelectionBounds = NSScreen.main?.visibleFrame ?? .zero
    }
}

// MARK: - Clipboard Restore

struct PendingClipboardRestore {
    let items: [NSPasteboardItem]

    private static var stateFileURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let parrotDir = dir.appendingPathComponent("Parrot")
        try? FileManager.default.createDirectory(at: parrotDir, withIntermediateDirectories: true)
        return parrotDir.appendingPathComponent("clipboard_state.json")
    }

    func persistToDisk() {
        let data = items.compactMap { item -> [String: Data]? in
            var dict: [String: Data] = [:]
            for type in item.types {
                if let d = item.data(forType: type) {
                    dict[type.rawValue] = d
                }
            }
            return dict.isEmpty ? nil : dict
        }
        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: Self.stateFileURL, options: .atomic)
        } catch {
            Logger.ax.error("AccessibilityBridge: failed to persist clipboard state — \(error.localizedDescription, privacy: .public)")
        }
    }

    func cleanupDiskState() {
        try? FileManager.default.removeItem(at: Self.stateFileURL)
    }

    static func restoreFromDiskIfAvailable() -> [NSPasteboardItem]? {
        guard let data = try? Data(contentsOf: stateFileURL),
              let plist = try? JSONDecoder().decode([[String: Data]].self, from: data) else {
            return nil
        }
        return plist.compactMap { dict -> NSPasteboardItem? in
            let item = NSPasteboardItem()
            for (typeRaw, data) in dict {
                item.setData(data, forType: NSPasteboard.PasteboardType(rawValue: typeRaw))
            }
            return item.types.isEmpty ? nil : item
        }
    }
}
