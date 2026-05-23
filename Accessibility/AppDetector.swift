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
              let appElement = AccessibilityBridge.asElementPublic(app) else {
            let fallback = await MainActor.run { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
            cachedBundleID = fallback
            cachedBundleIDTimestamp = Date()
            return fallback
        }

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

        let fallback = await MainActor.run { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
        cachedBundleID = fallback
        cachedBundleIDTimestamp = Date()
        return fallback
    }

    func frontAppName(from ref: CFTypeRef?) -> String {
        guard let element = ref, let axElement = AccessibilityBridge.asElementPublic(element) else { return "unknown" }
        var name: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            axElement,
            kAXTitleAttribute as CFString,
            &name
        )
        guard result == .success, let appName = name as? String else { return "unknown" }
        return appName
    }

    func isAIChatApp(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return aiChatBundleIDs.contains(bundleID)
            || aiChatBundleIDPrefixes.contains { bundleID.hasPrefix($0) }
    }

    private let aiChatBundleIDs: Set<String> = [
        "com.openai.chat",
        "com.anthropic.clause",
        "com.anthropic.clause.mac",
        "com.google.Chrome.app.chatgpt",
        "com.microsoft.VSCode",
        "com.github.GitHubClient",
        "com.copilot.VSCode",
    ]

    private let aiChatBundleIDPrefixes: [String] = [
        "com.anthropic.",
        "com.openai.",
        "com.google.Chrome.app.",
    ]
}
