import Cocoa

actor AccessibilityBridge {
    static let shared = AccessibilityBridge()

    private(set) var lastSelectionBounds: CGRect = .zero

    private static let _pidLock = NSLock()
    private nonisolated(unsafe) static var _storedPID: pid_t = 0

    nonisolated static var lastKnownFrontAppPID: pid_t {
        get { _pidLock.withLock { _storedPID } }
        set { _pidLock.withLock { _storedPID = newValue } }
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

        guard let frontApp = frontAppRef,
              CFGetTypeID(frontApp) == AXUIElementGetTypeID() else {
            throw CorrectionError.noTextSelected
        }
        let frontAppAX = frontApp as! AXUIElement

        var focusedRef: CFTypeRef?
        AXUIElementCopyAttributeValue(
            frontAppAX,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )

        guard let focusedElement = focusedRef,
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

        await MainActor.run {
            let pasteboard = NSPasteboard.general
            let originalChangeCount = pasteboard.changeCount
            var originalItems: [NSPasteboardItem] = []
            if let items = pasteboard.pasteboardItems {
                originalItems = items
            }

            pasteboard.clearContents()
            let item = NSPasteboardItem()
            item.setString(correctedText, forType: .string)
            pasteboard.writeObjects([item])

            let source = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x09), keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x09), keyDown: false)
            keyDown?.flags = CGEventFlags.maskCommand
            keyUp?.flags = CGEventFlags.maskCommand
            keyDown?.post(tap: CGEventTapLocation.cghidEventTap)
            keyUp?.post(tap: CGEventTapLocation.cghidEventTap)

            if !originalItems.isEmpty {
                let expectedChangeCount = originalChangeCount + 1
                let pasteboardData: [(String, Data)] = originalItems.compactMap { item in
                    let types = item.types
                    guard !types.isEmpty,
                          let type = types.first,
                          let data = item.data(forType: type) else { return nil }
                    return (type.rawValue, data)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(800)) {
                    let pb = NSPasteboard.general
                    guard pb.changeCount == expectedChangeCount else { return }
                    pb.clearContents()
                    for (rawType, data) in pasteboardData {
                        let item = NSPasteboardItem()
                        item.setData(data, forType: NSPasteboard.PasteboardType(rawType))
                        pb.writeObjects([item])
                    }
                }
            }
        }
    }

    func frontAppBundleID() async -> String? {
        await AppDetector.shared.frontAppBundleID()
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
