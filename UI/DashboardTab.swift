import SwiftUI

/// Overview of inline-completion usage: acceptance rate, savings, and session stats.
/// Data is collected in `StatsStore` on every show / accept / dismiss event.
struct DashboardTab: View {
    @State private var stats = StatsStore.StatsSnapshot(
        totalShown: 0, totalAccepted: 0, totalDismissed: 0,
        totalTypoFixes: 0, totalSnippetExpansions: 0,
        totalCharSavings: 0, firstUse: .now)
    @StateObject private var focusStats = FocusStatsStore.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Completions shown", value: "\(stats.totalShown)")
                LabeledContent("Accepted", value: "\(stats.totalAccepted)")
                LabeledContent("Dismissed", value: "\(stats.totalDismissed)")
                LabeledContent("Acceptance rate", value: acceptanceRate)
            } header: {
                Label("Usage", systemImage: "text.append")
            }

            Section {
                LabeledContent("Typo fixes", value: "\(stats.totalTypoFixes)")
                LabeledContent("Snippet expansions", value: "\(stats.totalSnippetExpansions)")
                LabeledContent("Characters saved", value: "\(stats.totalCharSavings)")
            } header: {
                Label("Details", systemImage: "chart.bar.fill")
            }

            Section {
                LabeledContent("Tracking since", value: stats.firstUse.formatted(date: .abbreviated, time: .shortened))
            } header: {
                Label("History", systemImage: "clock")
            } footer: {
                Text("Stats are stored locally and never sent anywhere.")
                    .foregroundStyle(.secondary)
            }

            // MARK: - Focus Stats
            Section {
                LabeledContent("Sessions completed", value: "\(focusStats.totalSessions)")
                LabeledContent("Writing time",
                               value: "\(focusStats.totalMinutes / 60)h \(focusStats.totalMinutes % 60)m")
                LabeledContent("Words in focus", value: "\(focusStats.totalWordsWritten)")
                LabeledContent("Current streak", value: focusStreakText)
                LabeledContent("Longest streak", value: "\(focusStats.longestStreak) day\(focusStats.longestStreak == 1 ? "" : "s")")
                if !focusStats.dailyLog.isEmpty {
                    weekHeatmap
                }
            } header: {
                Label("Focus", systemImage: "target")
            }
        }
        .formStyle(.grouped)
        .task { await load() }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            Task { await load() }
        }
    }

    private var acceptanceRate: String {
        let total = stats.totalAccepted + stats.totalDismissed
        guard total > 0 else { return "—" }
        let pct = Double(stats.totalAccepted) / Double(total) * 100
        return String(format: "%.1f%%", pct)
    }

    private func load() async {
        stats = await StatsStore.shared.stats()
        focusStats.loadIfNeeded()
    }

    // MARK: - Focus helpers

    private var focusStreakText: String {
        let s = focusStats.currentStreak
        guard s > 0 else { return "No sessions yet" }
        return "\(s) day\(s == 1 ? "" : "s") 🔥"
    }

    private var weekHeatmap: some View {
        let days = focusStats.weekHeatmap()
        return VStack(spacing: 4) {
            HStack(spacing: 6) {
                ForEach(days, id: \.label) { day in
                    VStack(spacing: 2) {
                        Text(day.label)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(day.active ? Color.accentColor : Color.secondary.opacity(0.12))
                            .frame(width: 20, height: 20)
                            .overlay(
                                Text("\(day.words)")
                                    .font(.caption2)
                                    .foregroundStyle(day.active ? .white : .clear)
                                    .minimumScaleFactor(0.5)
                            )
                    }
                }
            }
        }
    }
}
