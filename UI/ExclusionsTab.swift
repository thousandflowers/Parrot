import SwiftUI

struct ExclusionsTab: View {
    @Bindable var prefs: PreferencesStore

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(Array(prefs.excludedBundleIDs).sorted(), id: \.self) { bundleID in
                    HStack {
                        Image(systemName: "eye.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(bundleID)
                            .font(.callout)
                        Spacer()
                    }
                }
                .onDelete { indexSet in
                    let toDelete = indexSet.map { Array(prefs.excludedBundleIDs).sorted()[$0] }
                    for id in toDelete { prefs.removeExclusion(id) }
                }
            }
            .listStyle(.plain)

            Divider()

            HStack {
                Button("Add app…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.application]
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.message = "Select an app to exclude from automatic checks"
                    if panel.runModal() == .OK,
                       let url = panel.url,
                       let bundle = Bundle(url: url),
                       let id = bundle.bundleIdentifier {
                        prefs.addExclusion(id)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

#Preview {
    ExclusionsTab(prefs: PreferencesStore.shared)
}
