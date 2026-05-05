import Cocoa

actor AccessibilityBridge {
    static let shared = AccessibilityBridge()

    private(set) var lastSelectionBounds: CGRect = .zero
    private var cachedBundleID: String?
    private var cachedBundleIDTimestamp: Date = .distantPast

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

        guard appResult == .success, let frontApp = frontAppRef else {
            throw CorrectionError.textExtractionFailed(appName: appName(from: frontAppRef))
        }
        let frontAppAX = frontApp as! AXUIElement

        var focusedRef: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            frontAppAX,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )

        guard focusResult == .success, let focusedElement = focusedRef else {
            throw CorrectionError.noTextSelected
        }
        let axElement = focusedElement as! AXUIElement

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

    func replaceSelectedText(with correctedText: String) async throws {
        guard AXIsProcessTrusted() else {
            throw CorrectionError.accessibilityPermissionDenied
        }

        let systemAX = AXUIElementCreateSystemWide()

        var frontAppRef: CFTypeRef?
        AXUIElementCopyAttributeValue(
            systemAX,
            kAXFocusedApplicationAttribute as CFString,
            &frontAppRef
        )

        guard let frontApp = frontAppRef else {
            throw CorrectionError.noTextSelected
        }
        let frontAppAX = frontApp as! AXUIElement

        var focusedRef: CFTypeRef?
        AXUIElementCopyAttributeValue(
            frontAppAX,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )

        guard let focusedElement = focusedRef else {
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

        let pasteboard = NSPasteboard.general
        var originalItems: [NSPasteboardItem] = []
        if let items = pasteboard.pasteboardItems {
            originalItems = items
        }

        pasteboard.clearContents()
        pasteboard.setString(correctedText, forType: .string)

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x09), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x09), keyDown: false)
        keyDown?.flags = CGEventFlags.maskCommand
        keyUp?.flags = CGEventFlags.maskCommand
        keyDown?.post(tap: CGEventTapLocation.cghidEventTap)
        keyUp?.post(tap: CGEventTapLocation.cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
            pasteboard.clearContents()
            pasteboard.writeObjects(originalItems)
        }
    }

    func frontAppBundleID() async -> String? {
        if -cachedBundleIDTimestamp.timeIntervalSinceNow < 1, let cached = cachedBundleID {
            return cached
        }

        let systemAX = AXUIElementCreateSystemWide()

        var frontAppRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemAX,
            kAXFocusedApplicationAttribute as CFString,
            &frontAppRef
        )

        if result == .success, let app = frontAppRef {
            var bundleIDRef: CFTypeRef?
            let bundleResult = AXUIElementCopyAttributeValue(
                app as! AXUIElement,
                "AXBundleIdentifier" as CFString,
                &bundleIDRef
            )
            if bundleResult == .success, let id = bundleIDRef as? String {
                cachedBundleID = id
                cachedBundleIDTimestamp = Date()
                return id
            }
        }

        let fallback = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        cachedBundleID = fallback
        cachedBundleIDTimestamp = Date()
        return fallback
    }

    // MARK: - Private Helpers

    private func appName(from ref: CFTypeRef?) -> String {
        guard let element = ref else { return "unknown" }
        let axElement = element as! AXUIElement
        var name: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axElement, kAXTitleAttribute as CFString, &name)
        guard result == .success, let appName = name as? String else { return "unknown" }
        return appName
    }

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

            if boundsResult == .success, let boundsValue = boundsRef {
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
        if let app = frontAppRef {
            let axApp = app as! AXUIElement
            AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &frontWindowRef)
            if let window = frontWindowRef {
                let axWindow = window as! AXUIElement
                var pos: CFTypeRef?
                var size: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &pos)
                AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &size)

                if let p = pos, let s = size {
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
