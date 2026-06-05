import Foundation
import OSLog

/// Persistent stats for Focus Mode: sessions, streak, daily log.
///
/// Persisted as JSON in Application Support (parallel to StatsStore).
/// Not an actor — all mutations are MainActor (Focus Mode is UI-driven).
@MainActor
final class FocusStatsStore: ObservableObject {
    static let shared = FocusStatsStore()

    // MARK: - Published (UI reads these)

    @Published var totalSessions: Int = 0
    @Published var totalMinutes: Int = 0
    @Published var totalWordsWritten: Int = 0
    @Published var currentStreak: Int = 0
    @Published var longestStreak: Int = 0
    @Published var lastSessionDate: Date? = nil
    @Published var dailyLog: [String: DailyEntry] = [:]  // key = yyyy-MM-dd

    private var loaded = false

    struct DailyEntry: Codable, Equatable {
        var sessions: Int = 0
        var minutes: Int = 0
        var words: Int = 0
        var mood: String? = nil

        static let empty = DailyEntry()
    }

    private struct Persisted: Codable {
        var totalSessions: Int = 0
        var totalMinutes: Int = 0
        var totalWordsWritten: Int = 0
        var currentStreak: Int = 0
        var longestStreak: Int = 0
        var lastSessionDate: Date? = nil
        var dailyLog: [String: DailyEntry] = [:]
    }

    private static var fileURL: URL {
        let dir = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("Parrot")
        return dir.appendingPathComponent("focus_stats.json")
    }

    private init() {}

    // MARK: - API

    func recordSession(words: Int, minutes: Int, mood: String? = nil) {
        loadIfNeeded()
        totalSessions += 1
        totalMinutes += minutes
        totalWordsWritten += words
        lastSessionDate = .now

        let key = dateKey(.now)
        var entry = dailyLog[key] ?? .empty
        entry.sessions += 1
        entry.minutes += minutes
        entry.words += words
        if let m = mood { entry.mood = m }
        dailyLog[key] = entry

        recomputeStreak()
        save()
        objectWillChange.send()
    }

    func streakText() -> String {
        if currentStreak == 0 { return "No sessions yet" }
        return "\(currentStreak) day\(currentStreak == 1 ? "" : "s")"
    }

    var todayMinutes: Int {
        dailyLog[dateKey(.now)]?.minutes ?? 0
    }

    var todayWords: Int {
        dailyLog[dateKey(.now)]?.words ?? 0
    }

    /// Heatmap for the last 7 days: array of (dayLabel, words, hasSession)
    func weekHeatmap() -> [(label: String, words: Int, active: Bool)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let df = DateFormatter()
        df.dateFormat = "E"
        return (0..<7).reversed().map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: today)!
            let key = dateKey(date)
            let entry = dailyLog[key]
            return (
                label: String(df.string(from: date).prefix(2)),
                words: entry?.words ?? 0,
                active: entry != nil
            )
        }
    }

    // MARK: - Streak

    /// Pure streak computation: count consecutive days ending today that have a
    /// logged entry, allowing up to `freezeLimit` missing days to be skipped.
    /// `loggedKeys` are "yyyy-MM-dd" (POSIX) keys.
    static func computeStreak(loggedKeys: Set<String>, today: Date, freezeLimit: Int) -> Int {
        let cal = Calendar.current
        let df = DateFormatter()
        df.calendar = cal
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"

        var streak = 0
        var date = cal.startOfDay(for: today)
        var freezesUsed = 0

        while streak < 365 {
            let k = df.string(from: date)
            if loggedKeys.contains(k) {
                streak += 1
            } else if freezesUsed < freezeLimit {
                freezesUsed += 1
            } else {
                break
            }
            date = cal.date(byAdding: .day, value: -1, to: date)!
        }
        return streak
    }

    private func recomputeStreak() {
        let freeze = min(7, max(0, PreferencesStore.shared.focusStreakFreeze))
        let streak = Self.computeStreak(loggedKeys: Set(dailyLog.keys), today: .now, freezeLimit: freeze)
        currentStreak = streak
        if streak > longestStreak { longestStreak = streak }
    }

    // MARK: - Persistence

    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let d = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: d) else { return }
        totalSessions = decoded.totalSessions
        totalMinutes = decoded.totalMinutes
        totalWordsWritten = decoded.totalWordsWritten
        currentStreak = decoded.currentStreak
        longestStreak = decoded.longestStreak
        lastSessionDate = decoded.lastSessionDate
        dailyLog = decoded.dailyLog
    }

    private func save() {
        let persisted = Persisted(
            totalSessions: totalSessions,
            totalMinutes: totalMinutes,
            totalWordsWritten: totalWordsWritten,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            lastSessionDate: lastSessionDate,
            dailyLog: dailyLog
        )
        guard let d = try? JSONEncoder().encode(persisted) else { return }
        try? FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(),
                                                  withIntermediateDirectories: true)
        try? d.write(to: Self.fileURL, options: .atomic)
    }

    private func dateKey(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
}
