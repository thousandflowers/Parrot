import SwiftUI

struct AppRulesTab: View {
    @Bindable var prefs: PreferencesStore
    @State private var newBundleID = ""
    @State private var newDisplayName = ""

    var body: some View {
        VStack {
            List {
                ForEach(prefs.appRules) { rule in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.displayName).font(.headline)
                                Text(rule.bundleID)
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
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

                        HStack(spacing: 8) {
                            Picker("Servizio", selection: Binding(
                                get: { rule.serviceType },
                                set: { newValue in
                                    var updated = rule
                                    updated.serviceType = newValue
                                    prefs.updateAppRule(updated)
                                }
                            )) {
                                Text("Default").tag(ServiceType?.none)
                                ForEach(ServiceType.allCases.filter { $0 != .stub }, id: \.self) { st in
                                    Text(st.rawValue.capitalized).tag(ServiceType?.some(st))
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 140)

                            Picker("Prompt", selection: Binding(
                                get: { rule.promptID },
                                set: { newValue in
                                    var updated = rule
                                    updated.promptID = newValue
                                    prefs.updateAppRule(updated)
                                }
                            )) {
                                Text("Default").tag(UUID?.none)
                                ForEach(prefs.customPrompts) { prompt in
                                    Text(prompt.name).tag(UUID?.some(prompt.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 140)
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { indexSet in
                    let toDelete = indexSet.map { prefs.appRules[$0] }
                    for rule in toDelete {
                        prefs.deleteAppRule(rule)
                    }
                }
            }

            VStack(spacing: 8) {
                HStack {
                    TextField("Bundle ID (es. com.apple.Safari)", text: $newBundleID)
                    TextField("Nome (es. Safari)", text: $newDisplayName)
                    Button("Aggiungi") {
                        guard !newBundleID.isEmpty, !newDisplayName.isEmpty else { return }
                        prefs.addAppRule(AppRule(
                            bundleID: newBundleID,
                            displayName: newDisplayName
                        ))
                        newBundleID = ""
                        newDisplayName = ""
                    }
                    .disabled(newBundleID.isEmpty || newDisplayName.isEmpty)
                }

                Button("Aggiungi app corrente") {
                    Task {
                        if let bundleID = await AppDetector.shared.frontAppBundleID(),
                           bundleID != Bundle.main.bundleIdentifier,
                           !prefs.appRules.contains(where: { $0.bundleID == bundleID }) {
                            let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? bundleID
                            prefs.addAppRule(AppRule(
                                bundleID: bundleID,
                                displayName: appName
                            ))
                        }
                    }
                }
                .accessibilityHint("Aggiunge l'app attualmente in primo piano alla lista delle regole")
            }
            .padding()
        }
    }
}
