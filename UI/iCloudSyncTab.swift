import SwiftUI

struct iCloudSyncTab: View {
    @State private var selectedSections: Set<iCloudSyncSection> = [.preferences, .customRules]
    @State private var isAvailable = false
    @State private var syncMessage: String?
    @State private var syncFailures: [String] = []
    @State private var syncTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                HStack {
                    if isAvailable {
                        Label("iCloud is available", systemImage: "checkmark.icloud")
                            .font(.caption)
                            .foregroundStyle(Color.statusOk)
                            .accessibilityLabel("iCloud status: available")
                    } else {
                        Label("iCloud not available — check iCloud sign-in", systemImage: "exclamationmark.icloud")
                            .font(.caption)
                            .foregroundStyle(Color.statusWarning)
                            .accessibilityLabel("iCloud status: not available")
                    }
                }
                .transition(.opacity.combined(with: .slide))
                .animation(.easeOut(duration: 0.25), value: isAvailable)
            } header: {
                Text("Status")
            }

            Section {
                ForEach(iCloudSyncSection.allCases) { section in
                    Toggle(isOn: Binding(
                        get: { selectedSections.contains(section) },
                        set: { isSelected in
                            if isSelected { selectedSections.insert(section) }
                            else { selectedSections.remove(section) }
                        }
                    )) {
                        Label(section.label, systemImage: section.icon)
                    }
                }
            } header: {
                Text("Sync what?")
            } footer: {
                Text("Preferences: engine, language, shortcuts. Custom Rules: rules, prompts, presets, flows. History: past corrections.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 16) {
                    Button(action: syncToCloud) {
                        Label("Upload to iCloud", systemImage: "icloud.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isAvailable || selectedSections.isEmpty)

                    Button(action: syncFromCloud) {
                        Label("Download from iCloud", systemImage: "icloud.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isAvailable || selectedSections.isEmpty)
                }
                .padding(.vertical, 4)

                Group {
                    if let syncMessage {
                        Label(syncMessage, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.statusOk)
                            .accessibilityLabel(syncMessage)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.easeOut(duration: 0.2), value: syncMessage != nil)

                ForEach(syncFailures, id: \.self) { failure in
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.statusWarning)
                        .accessibilityLabel("Not uploaded: \(failure)")
                }
            } header: {
                Text("Actions")
            }
        }
        .formStyle(.grouped)
        .task {
            isAvailable = await iCloudSyncManager.shared.isAvailable
        }
    }

    private func syncToCloud() {
        syncTask?.cancel()
        syncFailures = []
        syncTask = Task {
            let report = await iCloudSyncManager.shared.syncToCloud(selectedSections: selectedSections)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                syncMessage = report.uploaded.isEmpty ? nil : "Uploaded \(report.uploaded.count) item(s) to iCloud"
                // Failures stay visible until the next sync: the user must notice data that did not sync.
                syncFailures = report.failed.map { "\($0.key.replacingOccurrences(of: "sync.", with: "")): \($0.reason)" }
            }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run { syncMessage = nil }
        }
    }

    private func syncFromCloud() {
        syncTask?.cancel()
        syncFailures = []
        syncTask = Task {
            let imported = await iCloudSyncManager.shared.syncFromCloud(selectedSections: selectedSections)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                syncMessage = "Downloaded \(imported.count) sections from iCloud"
            }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run { syncMessage = nil }
        }
    }
}

#Preview {
    iCloudSyncTab()
}
