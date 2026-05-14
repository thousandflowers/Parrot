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
                        Text(prompt.template).font(.caption).foregroundColor(.secondary)
                    }
                }
                .onDelete { indexSet in
                    let toDelete = indexSet.map { prefs.customPrompts[$0] }
                    for prompt in toDelete {
                        prefs.deleteCustomPrompt(prompt)
                    }
                }
            }

            HStack {
                TextField("Nome (es. Correzione formale)", text: $newPromptName, prompt: Text("Nome del prompt"))
                TextField("Template ({{TEXT}} = testo)", text: $newPromptTemplate, prompt: Text("Correggi {{TEXT}} con stile formale"))
                Button("Aggiungi") {
                    if !newPromptName.isEmpty, !newPromptTemplate.isEmpty {
                        let prompt = CustomPrompt(name: newPromptName, template: newPromptTemplate)
                        prefs.addCustomPrompt(prompt)
                        newPromptName = ""
                        newPromptTemplate = ""
                    }
                }
                .disabled(newPromptName.isEmpty || newPromptTemplate.isEmpty)
            }
            .padding()
        }
    }
}
