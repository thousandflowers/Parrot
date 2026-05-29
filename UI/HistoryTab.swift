import SwiftUI

struct HistoryTab: View {
    @State private var entries: [HistoryEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if entries.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.badge.checkmark")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.accentColor.opacity(0.5))
                            .accessibilityHidden(true)
                        Text("No corrections yet")
                            .font(.headline)
                        Text("Select text anywhere and press a shortcut.\nYour corrections will appear here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                } else {
                    List(entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Text(entry.original)
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                                    .lineLimit(1)
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundColor(.textSecondary)
                                Text(entry.corrected)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            Text(entry.timestamp, style: .relative)
                                .font(.caption2)
                                .foregroundColor(.textSecondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeOut(duration: 0.25), value: entries.isEmpty)
            Divider()
            HStack {
                Spacer()
                Button("Clear history") {
                    Task {
                        await HistoryStore.shared.clear()
                        guard !Task.isCancelled else { return }
                        entries = []
                    }
                }
                .padding(8)
            }
        }
        .task {
            entries = await HistoryStore.shared.all()
        }
        .onReceive(NotificationCenter.default.publisher(for: .historyDidChange)) { _ in
            Task {
                let result = await HistoryStore.shared.all()
                guard !Task.isCancelled else { return }
                entries = result
            }
        }
    }
}

#Preview {
    HistoryTab()
}
