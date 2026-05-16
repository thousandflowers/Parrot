import SwiftUI

struct AppRulesTab: View {
    @Bindable var prefs: PreferencesStore
    @State private var editingRule: AppRule?
    @State private var newBundleID = ""
    @State private var newDisplayName = ""

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(prefs.appRules) { rule in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.displayName).font(.headline)
                            Text(rule.bundleID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let serviceType = rule.serviceType {
                                Text("Servizio: \(serviceType.rawValue)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
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
                        .accessibilityLabel("Abilita regola per \(rule.displayName)")
                        Button {
                            editingRule = rule
                        } label: {
                            Image(systemName: "pencil")
                                .accessibilityLabel("Modifica regola")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { indexSet in
                    for idx in indexSet {
                        prefs.deleteAppRule(prefs.appRules[idx])
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Nuova Regola").font(.headline)
                HStack {
                    TextField("Bundle ID", text: $newBundleID, prompt: Text("com.apple.Safari"))
                    TextField("Nome", text: $newDisplayName, prompt: Text("Safari"))
                }
                HStack {
                    Spacer()
                    Button("Aggiungi") {
                        guard !newBundleID.isEmpty, !newDisplayName.isEmpty else { return }
                        prefs.addAppRule(AppRule(bundleID: newBundleID, displayName: newDisplayName))
                        newBundleID = ""
                        newDisplayName = ""
                    }
                    .disabled(newBundleID.isEmpty || newDisplayName.isEmpty)
                }
            }
            .padding()
        }
        .sheet(item: $editingRule) { rule in
            EditAppRuleSheet(rule: rule, availablePrompts: prefs.customPrompts) { updated in
                prefs.updateAppRule(updated)
                editingRule = nil
            } onCancel: {
                editingRule = nil
            }
        }
    }
}

private struct EditAppRuleSheet: View {
    @State private var isEnabled: Bool
    @State private var serviceType: ServiceType?
    @State private var promptID: UUID?

    private let original: AppRule
    private let availablePrompts: [CustomPrompt]
    private let onSave: (AppRule) -> Void
    private let onCancel: () -> Void

    init(
        rule: AppRule,
        availablePrompts: [CustomPrompt],
        onSave: @escaping (AppRule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.original = rule
        self.availablePrompts = availablePrompts
        self._isEnabled = State(initialValue: rule.isEnabled)
        self._serviceType = State(initialValue: rule.serviceType)
        self._promptID = State(initialValue: rule.promptID)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Modifica Regola").font(.headline)
            Text(original.bundleID).font(.caption).foregroundStyle(.secondary)

            LabeledContent("Abilitata") {
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .accessibilityLabel("Abilita regola per \(original.displayName)")
            }

            LabeledContent("Servizio") {
                Picker("Servizio", selection: $serviceType) {
                    Text("Predefinito").tag(ServiceType?.none)
                    ForEach(ServiceType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(ServiceType?.some(type))
                    }
                }
                .labelsHidden()
            }

            if !availablePrompts.isEmpty {
                LabeledContent("Prompt") {
                    Picker("Prompt", selection: $promptID) {
                        Text("Predefinito").tag(UUID?.none)
                        ForEach(availablePrompts) { prompt in
                            Text(prompt.name).tag(UUID?.some(prompt.id))
                        }
                    }
                    .labelsHidden()
                }
            }

            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { onCancel() }
                Button("Salva") {
                    var updated = original
                    updated.isEnabled = isEnabled
                    updated.serviceType = serviceType
                    updated.promptID = promptID
                    onSave(updated)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 320, minHeight: 240)
    }
}
