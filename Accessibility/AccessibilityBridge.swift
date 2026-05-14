import Cocoa

actor AccessibilityBridge {
    static let shared = AccessibilityBridge()

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
              CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
            throw CorrectionError.noTextSelected
        }
        return try await fetchTextOrLineAtCursor(from: (focusedElement as! AXUIElement))
    }

    /// Extracts text from the focused AX element. If a selection exists, returns it.
    /// If only a cursor is present (no selection), extracts the current line at the cursor.
    /// Returns the extracted text and the CFRange for targeted replacement.
    func fetchTextOrLineAtCursor(from element: AXUIElement?) async throws -> (text: String, range: CFRange) {
        guard let axElement = element else {
            throw CorrectionError.noTextSelected
        }
        // Try selected text first
        var selectedTextRef: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(
            axElement, kAXSelectedTextAttribute as CFString, &selectedTextRef
        )
        if textResult == .success, let selectedText = selectedTextRef as? String, !selectedText.isEmpty {
            await updateBounds(axElement: axElement)
            return (selectedText, lastSelectedRange)
        }
        // No selection — read cursor position and extract current line
        var rangeRef: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            axElement, kAXSelectedTextRangeAttribute as CFString, &rangeRef
        )
        var cursorRange = CFRange(location: 0, length: 0)
        if rangeResult == .success,
           let rangeValue = rangeRef,
           CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            AXValueGetValue(rangeValue as! AXValue, .cfRange, &cursorRange)
        }
        // Read full field text
        var valueRef: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            axElement, kAXValueAttribute as CFString, &valueRef
        )
        guard valueResult == .success,
              let fullText = valueRef as? String, !fullText.isEmpty else {
            throw CorrectionError.textExtractionFailed(appName: "unknown")
        }
        // Extract the line containing the cursor
        let nsText = fullText as NSString
        let cursorPos = cursorRange.length > 0 ? cursorRange.location : cursorRange.location
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
            axElement,
            kAXSelectedTextAttribute as CFString,
            &selectedTextRef
        )

        if textResult == .success, let selectedText = selectedTextRef as? String, !selectedText.isEmpty {
            await updateBounds(axElement: axElement)
            return selectedText
        }

        var valueRef: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXValueAttribute as CFString,
            &valueRef
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
            frontAppAX,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )

        guard focusResult == .success,
              let focusedElement = focusedRef,
              CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
            throw CorrectionError.noTextSelected
        }

        return try await extractText(from: focusedElement as! AXUIElement)
    }

    func fetchSelectedText() async throws -> String {
        guard AXIsProcessTrusted() else {
            throw CorrectionError.accessibilityPermissionDenied
        }

        let systemAX = AXUIElementCreateSystemWide()

        var frontAppRef: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(
            systemAX,
            kAXFocusedApplicationAttribute as CFString,
            &frontAppRef
        )

        guard appResult == .success,
              let frontApp = frontAppRef,
              CFGetTypeID(frontApp) == AXUIElementGetTypeID() else {
            throw CorrectionError.textExtractionFailed(appName: await AppDetector.shared.frontAppName(from: frontAppRef))
        }

        let frontAppAX = frontApp as! AXUIElement

        var focusedRef: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            frontAppAX,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )

        guard focusResult == .success,
              let focusedElement = focusedRef,
              CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
            throw CorrectionError.noTextSelected
        }

        return try await extractText(from: focusedElement as! AXUIElement)
    }

    func replaceSelectedText(with correctedText: String) async throws {
        guard AXIsProcessTrusted() else {
            throw CorrectionError.accessibilityPermissionDenied
        }

        let systemAX = AXUIElementCreateSystemWide()

        var frontAppRef: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(
            systemAX,
            kAXFocusedApplicationAttribute as CFString,
            &frontAppRef
        )

        guard appResult == .success,
              let frontApp = frontAppRef,
              CFGetTypeID(frontApp) == AXUIElementGetTypeID() else {
            throw CorrectionError.noTextSelected
        }
        let frontAppAX = frontApp as! AXUIElement

        var focusedRef: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            frontAppAX,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )

        guard focusResult == .success,
              let focusedElement = focusedRef,
              CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
            throw CorrectionError.noTextSelected
        }
        let axElement = focusedElement as! AXUIElement

        let setResult = AXUIElementSetAttributeValue(
            axElement,
            kAXSelectedTextAttribute as CFString,
            correctedText as CFTypeRef
        )

        if setResult == .success {
            return
        }

        let valueResult = AXUIElementSetAttributeValue(
            axElement,
            kAXValueAttribute as CFString,
            correctedText as CFTypeRef
        )

        if valueResult == .success {
            return
        }

        // Fallback: Clipboard injection
        try await injectViaClipboard(correctedText: correctedText)
    }

    private func injectViaClipboard(correctedText: String) async throws {
        let pasteboard = NSPasteboard.general
        let originalItems = pasteboard.pasteboardItems ?? []
        
        let pending = PendingClipboardRestore(
            items: originalItems,
            originalChangeCount: pasteboard.changeCount
        )
        
        // Se c'era già un ripristino in sospeso, forzalo ora
        if let existing = self.pendingClipboardRestore {
            restoreClipboard(existing)
        }
        
        pasteboard.clearContents()
        pasteboard.setString(correctedText, forType: .string)
        let newContentChangeCount = pasteboard.changeCount
        
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x09), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x09), keyDown: false) else {
            restoreClipboard(pending)
            return
        }
        keyDown.flags = CGEventFlags.maskCommand
        keyUp.flags = CGEventFlags.maskCommand
        keyDown.post(tap: CGEventTapLocation.cghidEventTap)
        keyUp.post(tap: CGEventTapLocation.cghidEventTap)
        
        guard !originalItems.isEmpty else { return }
        
        self.pendingClipboardRestore = pending
        
        // Aspettiamo che l'app target incolli. Poll di 500ms totali.
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(50))
            if self.pendingClipboardRestore?.originalChangeCount != pending.originalChangeCount {
                return // Un altro task ha preso il controllo
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

    // MARK: - Private Helpers

    private func updateBounds(axElement: AXUIElement) async {
        var rangeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(
            axElement,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        )

        if let rangeValue = rangeRef,
           CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            var boundsRef: CFTypeRef?
            let boundsResult = AXUIElementCopyParameterizedAttributeValue(
                axElement,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                rangeValue,
                &boundsRef
            )

            if boundsResult == .success,
               let boundsValue = boundsRef,
               CFGetTypeID(boundsValue) == AXValueGetTypeID() {
                let axValue = boundsValue as! AXValue
                var rect = CGRect()
                AXValueGetValue(axValue, .cgRect, &rect)
                self.lastSelectionBounds = rect
                return
            }
        }

        var frontWindowRef: CFTypeRef?
        let systemAX = AXUIElementCreateSystemWide()
        var frontAppRef: CFTypeRef?
        AXUIElementCopyAttributeValue(systemAX, kAXFocusedApplicationAttribute as CFString, &frontAppRef)
        if let app = frontAppRef, CFGetTypeID(app) == AXUIElementGetTypeID() {
            let axApp = app as! AXUIElement
            AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &frontWindowRef)
            if let window = frontWindowRef, CFGetTypeID(window) == AXUIElementGetTypeID() {
                let axWindow = window as! AXUIElement
                var pos: CFTypeRef?
                var size: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &pos)
                AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &size)

                if let p = pos, let s = size,
                   CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() {
                    let axPos = p as! AXValue
                    let axSize = s as! AXValue
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
