import SwiftUI

struct iCloudSyncTab: View {
    @State private var selectedSections: Set<String> = ["preferences", "customRules"]
    @State private var isAvailable = false
    @State private var syncMessage: String?
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
                        get: { selectedSections.contains(section.id.lowercased()) },
                        set: { isSelected in
                            let key = section.id.lowercased()
                            if isSelected { selectedSections.insert(key) }
                            else { selectedSections.remove(key) }
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
        syncTask = Task {
            await iCloudSyncManager.shared.syncToCloud(selectedSections: selectedSections)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                syncMessage = "Uploaded \(selectedSections.count) sections to iCloud"
            }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run { syncMessage = nil }
        }
    }

    private func syncFromCloud() {
        syncTask?.cancel()
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
