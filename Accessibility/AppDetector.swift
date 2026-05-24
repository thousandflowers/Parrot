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

    private let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "org.mozilla.firefox",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "io.boxy.Browser",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
    ]

    func isBrowser(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return browserBundleIDs.contains(bundleID)
    }

    /// Extract current URL from a browser's focused window via AX API.
    func currentBrowserURL(pid: pid_t) async -> URL? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let wr = windowRef,
              let windowElement = AccessibilityBridge.asElementPublic(wr) else { return nil }
        var docRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, "AXDocument" as CFString, &docRef) == .success,
              let docString = docRef as? String,
              docString.hasPrefix("http"),
              let url = URL(string: docString) else { return nil }
        return url
    }

    /// Map a URL's domain to a tone context note for the LLM prompt.
    nonisolated static func toneNote(for url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        if host.contains("linkedin.com") || host.contains("xing.com") {
            return "Context: writing for LinkedIn (professional network). Use a formal, professional tone."
        }
        if host.contains("twitter.com") || host.contains("x.com") {
            return "Context: writing for X/Twitter. Keep it concise and direct."
        }
        if host.contains("github.com") || host.contains("gitlab.com") {
            return "Context: writing for GitHub/GitLab. Use a technical, clear tone."
        }
        if host.contains("stackoverflow.com") {
            return "Context: writing for Stack Overflow. Use a technical, precise tone."
        }
        if host.contains("instagram.com") || host.contains("tiktok.com") {
            return "Context: writing for social media. Use an engaging, informal tone."
        }
        if host.contains(".edu") || host.contains("scholar.google") || host.contains("academia.edu") {
            return "Context: academic writing context. Use a formal, scholarly tone."
        }
        if host.contains("substack.com") || host.contains("medium.com") {
            return "Context: writing for a newsletter/blog. Use a clear, readable tone."
        }
        return nil
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
