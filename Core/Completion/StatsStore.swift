import Foundation

/// Tracks inline-completion usage stats for the Dashboard tab. Lightweight JSON persistence,
/// updated on every show / accept / dismiss event so the user sees live data.
actor StatsStore {
    static let shared = StatsStore()

    private struct Snapshot: Codable {
        var totalShown = 0
        var totalAccepted = 0
        var totalDismissed = 0
        var totalTypoFixes = 0
        var totalSnippetExpansions = 0
        var totalCharSavings = 0
        var firstUse: Date = .now
        var sessionStart: Date = .now
    }

    private var data = Snapshot()
    private var loaded = false

    /// Baselines captured the first time data is loaded this process, so session counters
    /// report deltas since app launch rather than lifetime totals.
    private var sessionBaseShown = 0
    private var sessionBaseAccepted = 0

    private static var fileURL: URL {
        let dir = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("Parrot")
        return dir.appendingPathComponent("completion_stats.json")
    }

    // MARK: - Queries (main-thread–safe read-only mirror)

    struct StatsSnapshot: Sendable {
        let totalShown: Int
        let totalAccepted: Int
        let totalDismissed: Int
        let totalTypoFixes: Int
        let totalSnippetExpansions: Int
        let totalCharSavings: Int
        let firstUse: Date
    }

    func stats() -> StatsSnapshot {
        loadIfNeeded()
        return StatsSnapshot(
            totalShown: data.totalShown,
            totalAccepted: data.totalAccepted,
            totalDismissed: data.totalDismissed,
            totalTypoFixes: data.totalTypoFixes,
            totalSnippetExpansions: data.totalSnippetExpansions,
            totalCharSavings: data.totalCharSavings,
            firstUse: data.firstUse
        )
    }

    /// Session-local counters (reset when the app restarts).
    func sessionShown() -> Int { loadIfNeeded(); return data.totalShown - sessionBaseShown }
    func sessionAccepted() -> Int { loadIfNeeded(); return data.totalAccepted - sessionBaseAccepted }

    // MARK: - Recording

    func recordShown() { loadIfNeeded(); data.totalShown += 1; save() }

    func recordAccepted(text: String) {
        loadIfNeeded()
        data.totalAccepted += 1
        data.totalCharSavings += text.count
        save()
    }

    func recordDismissed() { loadIfNeeded(); data.totalDismissed += 1; save() }

    func recordTypoFix() { loadIfNeeded(); data.totalTypoFixes += 1; save() }

    func recordSnippetExpansion() { loadIfNeeded(); data.totalSnippetExpansions += 1; save() }

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let d = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode(Snapshot.self, from: d) else { return }
        data = decoded
        sessionBaseShown = data.totalShown
        sessionBaseAccepted = data.totalAccepted
    }

    private func save() {
        guard let d = try? JSONEncoder().encode(data) else { return }
        try? FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(),
                                                  withIntermediateDirectories: true)
        try? d.write(to: Self.fileURL, options: .atomic)
    }
}
