import SwiftUI

struct PromptTab: View {
    @Bindable var prefs: PreferencesStore
    @State private var newPromptName = ""
    @State private var newPromptTemplate = ""

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(prefs.customPrompts) { prompt in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(prompt.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(prompt.template)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { indexSet in
                    let toDelete = indexSet.map { prefs.customPrompts[$0] }
                    for prompt in toDelete { prefs.deleteCustomPrompt(prompt) }
                }
            }
            .listStyle(.plain)

            Divider()

            HStack(spacing: 8) {
                TextField("Prompt name", text: $newPromptName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
                TextField("Template ({{TEXT}} = selected text)", text: $newPromptTemplate)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    guard !newPromptName.isEmpty, !newPromptTemplate.isEmpty else { return }
                    prefs.addCustomPrompt(CustomPrompt(name: newPromptName, template: newPromptTemplate))
                    newPromptName = ""
                    newPromptTemplate = ""
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newPromptName.isEmpty || newPromptTemplate.isEmpty)
            }
            .padding(12)
        }
    }
}

#Preview {
    PromptTab(prefs: PreferencesStore.shared)
}
