import Foundation

/// Builds a one-line style hint from the user's rejected corrections.
/// Used by PromptEngine to guide the LLM toward the user's preferred style.
enum StyleProfiler {
    private static let lock = NSLock()
    private static var cachedHint: String? = nil
    private static var cacheTimestamp: Date = .distantPast
    private static let cacheTTL: TimeInterval = 300  // rebuild at most once per 5 min

    /// Returns a style hint string or nil if insufficient data.
    static func buildHint(language: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if Date().timeIntervalSince(cacheTimestamp) < cacheTTL {
            return cachedHint
        }
        let hint = computeHint()
        cachedHint = hint
        cacheTimestamp = Date()
        return hint
    }

    static func invalidateCache() {
        lock.lock()
        defer { lock.unlock() }
        cacheTimestamp = .distantPast
    }

    private static func computeHint() -> String? {
        let entries = FeedbackLogger.recentEntries(limit: 30)
        guard !entries.isEmpty else { return nil }

        var rejectedPairs: [String: Int] = [:]
        for entry in entries {
            guard entry.original != entry.corrected else { continue }
            let origTokens = entry.original.split(separator: " ").map(String.init)
            let corrTokens = entry.corrected.split(separator: " ").map(String.init)
            let minLen = min(origTokens.count, corrTokens.count)
            for i in 0..<minLen {
                if origTokens[i] != corrTokens[i] {
                    let key = "'\(origTokens[i])' → '\(corrTokens[i])'"
                    rejectedPairs[key, default: 0] += 1
                    break
                }
            }
        }

        let top = rejectedPairs
            .sorted { $0.value > $1.value }
            .prefix(3)
            .filter { $0.value >= 2 }
            .map(\.key)

        guard !top.isEmpty else { return nil }
        return "User style note: user has previously rejected these corrections: \(top.joined(separator: ", ")). Avoid similar changes unless clearly required by grammar."
    }
}
