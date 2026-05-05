import Cocoa

actor AppDetector {
    static let shared = AppDetector()

    private var cachedBundleID: String?
    private var cachedBundleIDTimestamp: Date = .distantPast

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

    func frontAppName(from ref: CFTypeRef?) -> String {
        guard let element = ref else { return "unknown" }
        let axElement = element as! AXUIElement
        var name: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axElement, kAXTitleAttribute as CFString, &name)
        guard result == .success, let appName = name as? String else { return "unknown" }
        return appName
    }
}
