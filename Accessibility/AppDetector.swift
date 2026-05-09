import Cocoa

actor AppDetector {
    static let shared = AppDetector()

    private var cachedBundleID: String?
    private var cachedBundleIDTimestamp: Date = .distantPast

    func frontAppBundleID(forPID pid: pid_t) async -> String? {
        let appElement = AXUIElementCreateApplication(pid)

        var bundleIDRef: CFTypeRef?
        let bundleResult = AXUIElementCopyAttributeValue(
            appElement,
            "AXBundleIdentifier" as CFString,
            &bundleIDRef
        )
        if bundleResult == .success, let id = bundleIDRef as? String {
            return id
        }

        return await MainActor.run { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    }

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

        guard result == .success,
              let app = frontAppRef,
              CFGetTypeID(app) == AXUIElementGetTypeID() else {
            let fallback = await MainActor.run { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
            cachedBundleID = fallback
            cachedBundleIDTimestamp = Date()
            return fallback
        }

        let appElement = app as! AXUIElement

        var bundleIDRef: CFTypeRef?
        let bundleResult = AXUIElementCopyAttributeValue(
            appElement,
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
        guard let element = ref, CFGetTypeID(element) == AXUIElementGetTypeID() else { return "unknown" }
        let axElement = element as! AXUIElement
        var name: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            axElement,
            kAXTitleAttribute as CFString,
            &name
        )
        guard result == .success, let appName = name as? String else { return "unknown" }
        return appName
    }
}
