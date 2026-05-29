import SwiftUI

struct AppRulesTab: View {
    @Bindable var prefs: PreferencesStore
    @State private var newBundleID = ""
    @State private var newDisplayName = ""

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(prefs.appRules) { rule in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(rule.bundleID)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                            .accessibilityLabel("Enable rule for \(rule.displayName)")
                        }

                        HStack(spacing: 8) {
                            Picker("Service", selection: Binding(
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
                    for rule in toDelete { prefs.deleteAppRule(rule) }
                }
            }
            .listStyle(.plain)

            Divider()

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Bundle ID (e.g. com.apple.Safari)", text: $newBundleID)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Bundle ID")
                    TextField("Name (e.g. Safari)", text: $newDisplayName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Application name")
                    Button("Add") {
                        guard !newBundleID.isEmpty, !newDisplayName.isEmpty else { return }
                        prefs.addAppRule(AppRule(bundleID: newBundleID, displayName: newDisplayName))
                        newBundleID = ""
                        newDisplayName = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(newBundleID.isEmpty || newDisplayName.isEmpty)
                    .accessibilityLabel("Add")
                }

                Button("Add frontmost app") {
                    Task {
                        if let bundleID = await AppDetector.shared.frontAppBundleID(),
                           bundleID != Bundle.main.bundleIdentifier,
                           !prefs.appRules.contains(where: { $0.bundleID == bundleID }) {
                            let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? bundleID
                            prefs.addAppRule(AppRule(bundleID: bundleID, displayName: appName))
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint("Adds the currently frontmost app to the rules list")
            }
            .padding(12)
        }
    }
}

#Preview {
    AppRulesTab(prefs: PreferencesStore.shared)
}
