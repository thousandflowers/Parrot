import Cocoa

actor AccessibilityBridge: AXBridgeProtocol {
    static let shared = AccessibilityBridge()

    nonisolated private static func asElement(_ ref: CFTypeRef) -> AXUIElement? {
        CFGetTypeID(ref) == AXUIElementGetTypeID() ? (ref as! AXUIElement) : nil
    }

    nonisolated private static func asAXValue(_ ref: CFTypeRef) -> AXValue? {
        CFGetTypeID(ref) == AXValueGetTypeID() ? (ref as! AXValue) : nil
    }

    nonisolated static func asElementPublic(_ ref: CFTypeRef) -> AXUIElement? {
        asElement(ref)
    }

    private(set) var lastSelectionBounds: CGRect = .zero
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
        let setResult = AXUIElementSetAttributeValue(
            axElement, kAXSelectedTextAttribute as CFString, correctedText as CFTypeRef
        )
        if setResult == .success { return }
        let valueResult = AXUIElementSetAttributeValue(
            axElement, kAXValueAttribute as CFString, correctedText as CFTypeRef
        )
        if valueResult == .success { return }
        try await injectViaClipboard(correctedText: correctedText)
    }

    private func injectViaClipboard(correctedText: String) async throws {
        let pasteboard = NSPasteboard.general
        let originalItems: [NSPasteboardItem] = pasteboard.pasteboardItems?.compactMap { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        } ?? []

        if let existing = self.pendingClipboardRestore {
            restoreClipboard(existing)
            self.pendingClipboardRestore = nil
        }

        pasteboard.clearContents()
        pasteboard.setString(correctedText, forType: .string)
        let sentinelCount = pasteboard.changeCount

        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x09), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x09), keyDown: false) else {
            if !originalItems.isEmpty {
                restoreClipboard(PendingClipboardRestore(items: originalItems, originalChangeCount: sentinelCount))
            }
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        guard !originalItems.isEmpty else { return }

        let pending = PendingClipboardRestore(items: originalItems, originalChangeCount: sentinelCount)
        self.pendingClipboardRestore = pending

        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(50))
            if pasteboard.changeCount != sentinelCount {
                if self.pendingClipboardRestore?.originalChangeCount == pending.originalChangeCount {
                    restoreClipboard(pending)
                    self.pendingClipboardRestore = nil
                }
                return
            }
        }

        if self.pendingClipboardRestore?.originalChangeCount == pending.originalChangeCount {
            restoreClipboard(pending)
            self.pendingClipboardRestore = nil
        }
    }

    private func restoreClipboard(_ pending: PendingClipboardRestore) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(pending.items)
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

        var cfRange = range
        guard let axRangeValue = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, axRangeValue, &boundsRef
        ) == .success,
        let bv = boundsRef, let axBV = Self.asAXValue(bv) else { return nil }

        var rect = CGRect()
        AXValueGetValue(axBV, .cgRect, &rect)
        let screenH = NSScreen.main?.frame.height ?? 0
        return CGRect(x: rect.origin.x, y: screenH - rect.origin.y - rect.height,
                      width: rect.width, height: rect.height)
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
    let originalChangeCount: Int
}
