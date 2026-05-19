import SwiftUI

struct HistoryTab: View {
    @State private var entries: [HistoryEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No corrections yet",
                    systemImage: "clock",
                    description: Text("Applied corrections will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(entry.original)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(entry.corrected)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        Text(entry.timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Clear history") {
                    Task {
                        await HistoryStore.shared.clear()
                        entries = []
                    }
                }
                .padding(8)
            }
        }
        .task {
            entries = await HistoryStore.shared.all()
        }
    }
}
