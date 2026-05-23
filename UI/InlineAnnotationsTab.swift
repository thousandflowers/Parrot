import SwiftUI

struct InlineAnnotationsTab: View {
    @Bindable var prefs: PreferencesStore
    @State private var runningApps: [NSRunningApplication] = []

    var body: some View {
        Form {
            Section {
                Toggle("Hover-only mode", isOn: $prefs.inlineAnnotationsHoverOnly)
            } header: {
                Label("Display", systemImage: "eye")
            } footer: {
                Text("When enabled, underlines appear only when you hover over an error — no permanent overlay.")
                    .foregroundStyle(.secondary)
            }

            Section {
                if prefs.treeTraversalDisabledBundleIDs.isEmpty {
                    Text("All apps")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(Array(prefs.treeTraversalDisabledBundleIDs).sorted(), id: \.self) { bundleID in
                        HStack {
                            appIcon(for: bundleID)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(appName(for: bundleID))
                                    .font(.callout)
                                Text(bundleID)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button {
                                prefs.enableTreeTraversal(bundleID)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Re-enable deep scan for this app")
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Label("Deep AX scan enabled", systemImage: "arrow.triangle.branch")
            } footer: {
                Text("When the focused element doesn't expose text bounds, Parrot walks the accessibility tree to find them. Disable per app if you notice slowness.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Disable for app…") {
                    pickApp { bundleID in
                        prefs.disableTreeTraversal(bundleID)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if !runningApps.isEmpty {
                    Divider()
                    Text("Running apps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(runningApps, id: \.processIdentifier) { app in
                        if let bid = app.bundleIdentifier {
                            let disabled = prefs.isTreeTraversalDisabled(bundleID: bid)
                            Toggle(isOn: Binding(
                                get: { !disabled },
                                set: { enabled in
                                    if enabled { prefs.enableTreeTraversal(bid) }
                                    else { prefs.disableTreeTraversal(bid) }
                                }
                            )) {
                                HStack(spacing: 6) {
                                    appIcon(for: bid)
                                    Text(app.localizedName ?? bid)
                                        .font(.callout)
                                }
                            }
                        }
                    }
                }
            } header: {
                Label("Quick toggle", systemImage: "slider.horizontal.3")
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshRunningApps() }
    }

    private func refreshRunningApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func pickApp(completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select an app to disable deep AX scan"
        if panel.runModal() == .OK,
           let url = panel.url,
           let bundle = Bundle(url: url),
           let id = bundle.bundleIdentifier {
            completion(id)
        }
    }

    private func appName(for bundleID: String) -> String {
        NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID })?.localizedName
            ?? bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    @ViewBuilder
    private func appIcon(for bundleID: String) -> some View {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }),
           let icon = app.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "app")
                .frame(width: 18, height: 18)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    InlineAnnotationsTab(prefs: PreferencesStore.shared)
}
