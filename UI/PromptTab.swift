import SwiftUI

struct PromptTab: View {
    @Bindable var prefs: PreferencesStore
    @State private var editingPrompt: CustomPrompt?
    @State private var showingAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(prefs.customPrompts) { prompt in
                    HStack(spacing: 10) {
                        Image(systemName: prompt.icon)
                            .foregroundColor(.accentColor)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(prompt.name).font(.headline)
                                if let key = prompt.shortcutKey {
                                    Text("Cmd+Shift+\(key)")
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.quaternary)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                            Text(prompt.template)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Modifica") { editingPrompt = prompt }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { indexSet in
                    let toDelete = indexSet.map { prefs.customPrompts[$0] }
                    for prompt in toDelete { prefs.deleteCustomPrompt(prompt) }
                }
            }

            Divider()

            HStack {
                Text("Usa {{TEXT}} nel template per il testo selezionato")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Aggiungi prompt") { showingAddSheet = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showingAddSheet) {
            PromptEditSheet(prefs: prefs, prompt: nil)
        }
        .sheet(item: $editingPrompt) { prompt in
            PromptEditSheet(prefs: prefs, prompt: prompt)
        }
    }
}

struct PromptEditSheet: View {
    let prefs: PreferencesStore
    let prompt: CustomPrompt?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var template: String
    @State private var icon: String
    @State private var shortcutKey: String

    init(prefs: PreferencesStore, prompt: CustomPrompt?) {
        self.prefs = prefs
        self.prompt = prompt
        _name = State(initialValue: prompt?.name ?? "")
        _template = State(initialValue: prompt?.template ?? "")
        _icon = State(initialValue: prompt?.icon ?? "pencil")
        _shortcutKey = State(initialValue: prompt?.shortcutKey ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(prompt == nil ? "Nuovo Prompt" : "Modifica Prompt")
                .font(.title2.bold())

            TextField("Nome del prompt", text: $name)
            TextField("Template (usa {{TEXT}} per il testo)", text: $template, axis: .vertical)
                .lineLimit(4...8)
            TextField("Icona SF Symbol (es. wand.and.stars)", text: $icon)
            TextField("Tasto scorciatoia (es. 1, 2, 3)", text: $shortcutKey)
                .help("Combinazione Cmd+Shift+[tasto] per attivare questo prompt")

            HStack {
                Button("Annulla") { dismiss() }
                Spacer()
                Button(prompt == nil ? "Aggiungi" : "Salva") {
                    let p = CustomPrompt(
                        id: prompt?.id ?? UUID(),
                        name: name, template: template, icon: icon.isEmpty ? "pencil" : icon,
                        shortcutKey: shortcutKey.isEmpty ? nil : shortcutKey
                    )
                    if prompt == nil {
                        prefs.addCustomPrompt(p)
                    } else {
                        prefs.updateCustomPrompt(p)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || template.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 400)
    }
}
