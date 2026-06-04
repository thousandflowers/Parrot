import SwiftUI

/// Overview of inline-completion usage: acceptance rate, savings, and session stats.
/// Data is collected in `StatsStore` on every show / accept / dismiss event.
struct DashboardTab: View {
    @State private var stats = StatsStore.StatsSnapshot(
        totalShown: 0, totalAccepted: 0, totalDismissed: 0,
        totalTypoFixes: 0, totalSnippetExpansions: 0,
        totalCharSavings: 0, firstUse: .now)

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
    }
}
