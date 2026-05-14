import SwiftUI

struct AppRulesTab: View {
    @Bindable var prefs: PreferencesStore
    @State private var newBundleID = ""
    @State private var newDisplayName = ""

    var body: some View {
        VStack {
            List {
                ForEach(prefs.appRules) { rule in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.displayName).font(.headline)
                            Text(rule.bundleID)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { rule.isEnabled },
                            set: { newValue in
                                var updated = rule
                                updated.isEnabled = newValue
                                prefs.updateAppRule(updated)
                            }
                        ))
                        .labelsHidden()
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { indexSet in
                    let toDelete = indexSet.map { prefs.appRules[$0] }
                    for rule in toDelete {
                        prefs.deleteAppRule(rule)
                    }
                }
            }

            HStack {
                TextField("Bundle ID (es. com.apple.Safari)", text: $newBundleID, prompt: Text("com.apple.Safari"))
                TextField("Nome visualizzato (es. Safari)", text: $newDisplayName, prompt: Text("Safari"))
                Button("Aggiungi") {
                    if !newBundleID.isEmpty, !newDisplayName.isEmpty {
                        prefs.addAppRule(AppRule(bundleID: newBundleID, displayName: newDisplayName))
                        newBundleID = ""
                        newDisplayName = ""
                    }
                }
                .disabled(newBundleID.isEmpty || newDisplayName.isEmpty)
            }
            .padding()
        }
    }
}
