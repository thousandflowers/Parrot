import SwiftUI

struct CustomRulesView: View {
    @State private var rules: [CustomRule] = []
    @State private var showingAddRule = false
    @State private var editingRule: CustomRule?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Custom Rules")
                    .font(.headline)
                Spacer()
                Button(action: { showingAddRule = true }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Add rule")
            }
            .padding()

            if rules.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No custom rules")
                        .font(.title3)
                    Text("Add rules to correct specific patterns in your text")
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
                    let result = await CustomRuleStore.shared.allRules()
                    guard !Task.isCancelled else { return }
                    rules = result
                }
                showingAddRule = false
            })
        }
        .sheet(item: $editingRule) { rule in
            EditRuleView(rule: rule, onSave: { updatedRule in
                Task {
                    await CustomRuleStore.shared.update(updatedRule)
                    let result = await CustomRuleStore.shared.allRules()
                    guard !Task.isCancelled else { return }
                    rules = result
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
                    Text(rule.name.isEmpty ? "Unnamed" : rule.name)
                        .font(.system(.body, design: .rounded).weight(.medium))
                    if !rule.isEnabled {
                        Text("Disabled")
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
                .help("Edit")
                .accessibilityLabel("Edit rule")
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.statusError)
                .help("Delete")
                .accessibilityLabel("Delete rule")
            }
        }
        .padding(.vertical, 4)
    }
}

struct EditRuleView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Bool
    @State private var rule: CustomRule
    let onSave: (CustomRule) -> Void

    init(rule: CustomRule, onSave: @escaping (CustomRule) -> Void) {
        _rule = State(initialValue: rule)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Rule name", text: $rule.name)
                    .focused($focusedField)
            }
            Section("Pattern") {
                TextField("Search for", text: $rule.pattern)
                    .font(.system(.body, design: .monospaced))
                TextField("Replace with", text: $rule.replacement)
                    .font(.system(.body, design: .monospaced))
            }
            Section("Options") {
                Toggle("Use regex", isOn: $rule.isRegex)
                Toggle("Case sensitive", isOn: $rule.isCaseSensitive)
                Picker("Language", selection: $rule.language) {
                    Text("All languages").tag("any")
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
        .onAppear { focusedField = true }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(rule)
                }
                .disabled(rule.pattern.isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

#Preview {
    CustomRulesView()
}

#Preview {
    EditRuleView(rule: CustomRule(
        name: "Fix quotes",
        pattern: "\"(.+?)\"",
        replacement: "「$1」",
        isEnabled: true,
        isRegex: true,
        isCaseSensitive: false,
        language: "any"
    ), onSave: { _ in })
        .frame(width: 420)
}
