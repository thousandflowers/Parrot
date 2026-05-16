import SwiftUI

struct CustomRulesView: View {
    @State private var rules: [CustomRule] = []
    @State private var showingAddRule = false
    @State private var editingRule: CustomRule?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Regole Personalizzate")
                    .font(.headline)
                Spacer()
                Button(action: { showingAddRule = true }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding()

            if rules.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Nessuna regola personalizzata")
                        .font(.title3)
                    Text("Aggiungi regole per correggere pattern specifici nel tuo testo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(rules) { rule in
                    CustomRuleRow(rule: rule) {
                        editingRule = rule
                    } onDelete: {
                        Task { await CustomRuleStore.shared.remove(id: rule.id) }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .task {
            rules = await CustomRuleStore.shared.allRules()
        }
        .sheet(isPresented: $showingAddRule) {
            EditRuleView(rule: CustomRule(), onSave: { rule in
                Task {
                    await CustomRuleStore.shared.add(rule)
                    rules = await CustomRuleStore.shared.allRules()
                }
                showingAddRule = false
            })
        }
        .sheet(item: $editingRule) { rule in
            EditRuleView(rule: rule, onSave: { updatedRule in
                Task {
                    await CustomRuleStore.shared.update(updatedRule)
                    rules = await CustomRuleStore.shared.allRules()
                }
                editingRule = nil
            })
        }
    }
}

struct CustomRuleRow: View {
    let rule: CustomRule
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(rule.name.isEmpty ? "Senza nome" : rule.name)
                        .font(.system(.body, design: .rounded).weight(.medium))
                    if !rule.isEnabled {
                        Text("Disabilitata")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.2), in: .capsule)
                    }
                }
                HStack(spacing: 8) {
                    Label(rule.pattern, systemImage: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Label(rule.replacement, systemImage: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Modifica")
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Elimina")
            }
        }
        .padding(.vertical, 4)
    }
}

struct EditRuleView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rule: CustomRule
    let onSave: (CustomRule) -> Void

    init(rule: CustomRule, onSave: @escaping (CustomRule) -> Void) {
        _rule = State(initialValue: rule)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Identità") {
                TextField("Nome regola", text: $rule.name)
            }
            Section("Pattern") {
                TextField("Cosa cercare", text: $rule.pattern)
                    .font(.system(.body, design: .monospaced))
                TextField("Sostituisci con", text: $rule.replacement)
                    .font(.system(.body, design: .monospaced))
            }
            Section("Opzioni") {
                Toggle("Usa regex", isOn: $rule.isRegex)
                Toggle("Case sensitive", isOn: $rule.isCaseSensitive)
                Picker("Lingua", selection: $rule.language) {
                    Text("Tutte le lingue").tag("any")
                    Divider()
                    Text("Italiano").tag("it")
                    Text("English").tag("en")
                    Text("Français").tag("fr")
                    Text("Deutsch").tag("de")
                    Text("Español").tag("es")
                    Text("Português").tag("pt")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") {
                    onSave(rule)
                }
                .disabled(rule.pattern.isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Annulla") { dismiss() }
            }
        }
    }
}

#Preview {
    CustomRulesView()
}
