import Foundation

/// Broad category of the currently focused application, used to pick a per-domain debounce
/// floor. Browser apps emit more spurious AX events (JS rendering pipelines) so they benefit
/// from a longer minimum delay; terminals see very fast typing and want the shortest window.
enum AppDebounceCategory: String, CaseIterable {
    case browser
    case native
    case terminal

    static func detect(bundleID: String?) -> AppDebounceCategory {
        guard let id = bundleID?.lowercased() else { return .native }
        let browserPrefixes = ["com.google.chrome", "com.apple.safari", "org.mozilla.firefox",
                               "com.microsoft.edgemac", "com.brave.browser", "com.operasoftware.opera",
                               "com.vivaldi.vivaldi", "com.torchbrowser.torch", "company.thebrowser.browser",
                               "com.apple.webkit"]
        if browserPrefixes.contains(where: { id.hasPrefix($0) }) { return .browser }
        let terminalPrefixes = ["com.googlecode.iterm2", "com.apple.terminal", "com.warp.warp",
                                "com.mitchellh.ghostty", "app.alacritty", "co.zeit.hyper",
                                "com.sourcetree.sourcetree", "com.microsoft.vscode"]
        if terminalPrefixes.contains(where: { id.hasPrefix($0) }) { return .terminal }
        return .native
    }
}

/// Picks a debounce delay from how fast the user is typing. A long gap since the last keystroke
/// means they paused → fire fast (minMs). Rapid keystrokes → wait longer (toward maxMs) so we do
/// not burn inference on text that is about to change.
///
/// Per-domain base delays:
///   browser → min 140 ms (more AX noise, JS rendering lag)
///   native  → min  80 ms (clean AX, faster caret-response)
///   terminal → min  50 ms (fastest typing pattern)
struct AdaptiveDebounce {
    let minMs: Int
    let maxMs: Int

    init(minMs: Int = 140, maxMs: Int = 300) { self.minMs = minMs; self.maxMs = maxMs }

    /// Minimum delay for each domain category. Used as the "paused" floor.
    static func minMs(for category: AppDebounceCategory) -> Int {
        switch category {
        case .browser:  return 140
        case .native:   return 80
        case .terminal: return 50
        }
    }

    func nextDelayMs(sinceLastKeystrokeMs: Int, category: AppDebounceCategory = .native) -> Int {
        let effectiveMin = min(Self.minMs(for: category), maxMs)
        if sinceLastKeystrokeMs >= maxMs { return effectiveMin }
        if sinceLastKeystrokeMs <= 0 { return maxMs }
        let fraction = Double(sinceLastKeystrokeMs) / Double(maxMs)
        let delay = Double(maxMs) - fraction * Double(maxMs - effectiveMin)
        return Int(delay.rounded())
    }
}
