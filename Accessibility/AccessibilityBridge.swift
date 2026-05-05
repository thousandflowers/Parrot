import Cocoa

actor AccessibilityBridge {
    static let shared = AccessibilityBridge()

    private(set) var lastSelectionBounds: CGRect = .zero

    func fetchSelectedText() async throws -> String {
        guard AXIsProcessTrusted() else {
            throw CorrectionError.accessibilityPermissionDenied
        }

        let systemAX = AXUIElementCreateSystemWide()

        var frontAppRef: CFTypeRef?
        defer { if let ref = frontAppRef { CFRelease(ref) } }
        let appResult = AXUIElementCopyAttributeValue(
            systemAX,
            kAXFocusedApplicationAttribute as CFString,
            &frontAppRef
        )

        guard appResult == .success,
              let frontApp = frontAppRef,
              let frontAppAX = frontApp as? AXUIElement else {
            throw CorrectionError.textExtractionFailed(appName: appName(from: frontAppRef))
        }

        var focusedRef: CFTypeRef?
        defer { if let ref = focusedRef { CFRelease(ref) } }
        let focusResult = AXUIElementCopyAttributeValue(
            frontAppAX,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )

        guard focusResult == .success,
              let focusedElement = focusedRef,
              let axElement = focusedElement as? AXUIElement else {
            throw CorrectionError.noTextSelected
        }

        var selectedTextRef: CFTypeRef?
        defer { if let ref = selectedTextRef { CFRelease(ref) } }
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
        defer { if let ref = valueRef { CFRelease(ref) } }
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

    func replaceSelectedText(with correctedText: String) async throws {
        guard AXIsProcessTrusted() else {
            throw CorrectionError.accessibilityPermissionDenied
        }

        let systemAX = AXUIElementCreateSystemWide()

        var frontAppRef: CFTypeRef?
        defer { if let ref = frontAppRef { CFRelease(ref) } }
        AXUIElementCopyAttributeValue(
            systemAX,
            kAXFocusedApplicationAttribute as CFString,
            &frontAppRef
        )

        guard let frontApp = frontAppRef,
              let frontAppAX = frontApp as? AXUIElement else {
            throw CorrectionError.noTextSelected
        }

        var focusedRef: CFTypeRef?
        defer { if let ref = focusedRef { CFRelease(ref) } }
        AXUIElementCopyAttributeValue(
            frontAppAX,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )

        guard let focusedElement = focusedRef,
              let axElement = focusedElement as? AXUIElement else {
            throw CorrectionError.noTextSelected
        }

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

        let pasteboard = NSPasteboard.general
        var originalItems: [NSPasteboardItem] = []
        if let items = pasteboard.pasteboardItems {
            originalItems = items
        }

        pasteboard.clearContents()
        pasteboard.setString(correctedText, forType: .string)

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
            pasteboard.clearContents()
            pasteboard.writeObjects(originalItems)
        }
    }

    // MARK: - Private Helpers

    private func appName(from ref: CFTypeRef?) -> String {
        guard let element = ref as? AXUIElement else { return "unknown" }
        var name: CFTypeRef?
        defer { if let ref = name { CFRelease(ref) } }
        let result = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &name)
        guard result == .success, let appName = name as? String else { return "unknown" }
        return appName
    }

    private func updateBounds(axElement: AXUIElement) async {
        var rangeRef: CFTypeRef?
        defer { if let ref = rangeRef { CFRelease(ref) } }
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

            defer { if let ref = boundsRef { CFRelease(ref) } }
            if boundsResult == .success, let boundsValue = boundsRef as? AXValue {
                var rect = CGRect()
                AXValueGetValue(boundsValue, .cgRect, &rect)
                self.lastSelectionBounds = rect
                return
            }
        }

        var frontWindowRef: CFTypeRef?
        let systemAX = AXUIElementCreateSystemWide()
        var frontAppRef: CFTypeRef?
        defer { if let ref = frontAppRef { CFRelease(ref) } }
        AXUIElementCopyAttributeValue(systemAX, kAXFocusedApplicationAttribute as CFString, &frontAppRef)
        if let app = frontAppRef as? AXUIElement {
            defer { if let ref = frontWindowRef { CFRelease(ref) } }
            AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &frontWindowRef)
            if let window = frontWindowRef as? AXUIElement {
                var pos: CFTypeRef?
                var size: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &pos)
                AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size)

                defer { if let r = pos { CFRelease(r) }; if let r = size { CFRelease(r) } }
                if let p = pos as? AXValue, let s = size as? AXValue {
                    var point = CGPoint()
                    var sz = CGSize()
                    AXValueGetValue(p, .cgPoint, &point)
                    AXValueGetValue(s, .cgSize, &sz)
                    self.lastSelectionBounds = CGRect(origin: point, size: sz)
                    return
                }
            }
        }

        self.lastSelectionBounds = NSScreen.main?.visibleFrame ?? .zero
    }
}
