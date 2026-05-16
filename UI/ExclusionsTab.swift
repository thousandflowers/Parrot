import SwiftUI

struct ExclusionsTab: View {
    @Bindable var prefs: PreferencesStore

    var body: some View {
        VStack {
            if prefs.excludedBundleIDs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Nessuna app esclusa")
                        .foregroundStyle(.secondary)
                    Text("Tutte le app vengono controllate automaticamente")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(prefs.excludedBundleIDs).sorted(), id: \.self) { bundleID in
                        HStack {
                            Text(bundleID)
                            Spacer()
                            Text("escluso")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        let toDelete = indexSet.map { Array(prefs.excludedBundleIDs).sorted()[$0] }
                        for id in toDelete {
                            prefs.removeExclusion(id)
                        }
                    }
                }
                .accessibilityLabel("App escluse dal controllo automatico")
            }

            HStack {
                Button("Aggiungi app") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.application]
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.message = "Seleziona un'app da escludere dal controllo automatico"
                    if panel.runModal() == .OK,
                       let url = panel.url,
                       let bundle = Bundle(url: url),
                       let id = bundle.bundleIdentifier {
                        prefs.addExclusion(id)
                    }
                }
                Spacer()
            }
            .padding()
        }
    }
}
