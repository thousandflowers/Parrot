import SwiftUI

struct PromptTab: View {
    @Bindable var prefs: PreferencesStore
    @State private var newPromptName = ""
    @State private var newPromptTemplate = ""

    var body: some View {
        VStack {
            List {
                ForEach(prefs.customPrompts) { prompt in
                    VStack(alignment: .leading) {
                        Text(prompt.name).font(.headline)
                        Text(prompt.template).font(.caption).foregroundColor(.textSecondary)
                    }
                }
                .onDelete { indexSet in
                    let toDelete = indexSet.map { prefs.customPrompts[$0] }
                    for prompt in toDelete { prefs.deleteCustomPrompt(prompt) }
                }
            }

            HStack {
                TextField("Nome", text: $newPromptName)
                TextField("Template ({{TEXT}} = testo)", text: $newPromptTemplate)
                Button("Aggiungi") {
                    guard !newPromptName.isEmpty, !newPromptTemplate.isEmpty else { return }
                    prefs.addCustomPrompt(CustomPrompt(name: newPromptName, template: newPromptTemplate))
                    newPromptName = ""
                    newPromptTemplate = ""
                }
                .disabled(newPromptName.isEmpty || newPromptTemplate.isEmpty)
            }
            .padding()
        }
    }
}
