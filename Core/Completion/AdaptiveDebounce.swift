import Foundation

/// Broad category of the currently focused application, used to pick a per-domain debounce
/// floor. Browser apps emit more spurious AX events (JS rendering pipelines) so they benefit
/// from a longer minimum delay; terminals see very fast typing and want the shortest window.
enum AppDebounceCategory: String, CaseIterable {
    case browser
    case native
    case terminal

    static func detect(bundleID: String?) -> AppDebounceCategory {
        // Single source of truth for app classification is `AppDetector` (canonical, case-sensitive
        // bundle IDs). The old inline lists here drifted from it — e.g. they classed VSCode as a
        // terminal (it is a code editor) and lowercased the ID, which would also have broken
        // AppDetector's case-sensitive matching. Code editors fall through to `.native` (clean AX,
        // standard typing cadence).
        guard let id = bundleID else { return .native }
        if AppDetector.isBrowser(id) { return .browser }
        if AppDetector.isTerminal(id) { return .terminal }
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
    let maxMs: Int

    // The "paused" floor is per-domain (see `minMs(for:)`), not a single instance value — an earlier
    // instance `minMs` was silently ignored by `nextDelayMs` once the per-category floors landed.
    init(maxMs: Int = 300) { self.maxMs = maxMs }

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
