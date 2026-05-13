import SwiftUI

struct ExclusionsTab: View {
    @Bindable var prefs: PreferencesStore

    var body: some View {
        VStack {
            List {
                ForEach(Array(prefs.excludedBundleIDs).sorted(), id: \.self) { bundleID in
                    HStack {
                        Text(bundleID)
                        Spacer()
                        Text("escluso")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                }
                .onDelete { indexSet in
                    let toDelete = indexSet.map { Array(prefs.excludedBundleIDs).sorted()[$0] }
                    for id in toDelete { prefs.removeExclusion(id) }
                }
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
