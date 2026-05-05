import Cocoa

actor AppDetector {
    static let shared = AppDetector()

    private var cachedBundleID: String?
    private var cachedBundleIDTimestamp: Date = .distantPast

    func frontAppBundleID() async -> String? {
        if Date().timeIntervalSince(cachedBundleIDTimestamp) < 1, let cached = cachedBundleID {
            return cached
        }

        let systemAX = AXUIElementCreateSystemWide()

        var frontAppRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemAX,
            kAXFocusedApplicationAttribute as CFString,
            &frontAppRef
        )

        guard result == .success, let app = frontAppRef else {
            let fallback = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            cachedBundleID = fallback
            cachedBundleIDTimestamp = Date()
            return fallback
        }

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

        let fallback = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        cachedBundleID = fallback
        cachedBundleIDTimestamp = Date()
        return fallback
    }

    func frontAppName(from ref: CFTypeRef?) -> String {
        guard let element = ref else { return "unknown" }
        var name: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXTitleAttribute as CFString,
            &name
        )
        guard result == .success, let appName = name as? String else { return "unknown" }
        return appName
    }
}
