import SwiftUI

struct SettingsView: View {
    @State private var prefs = PreferencesStore.shared

    var body: some View {
        TabView {
            GeneralTab(prefs: prefs)
                .tabItem { Label("Generale", systemImage: "gearshape") }

            ModelsTab(prefs: prefs)
                .tabItem { Label("Modelli", systemImage: "brain") }

            PromptTab(prefs: prefs)
                .tabItem { Label("Prompt", systemImage: "text.quote") }

            AppRulesTab(prefs: prefs)
                .tabItem { Label("Regole App", systemImage: "apps.iphone") }

            ExclusionsTab(prefs: prefs)
                .tabItem { Label("Esclusioni", systemImage: "eye.slash") }

            AdvancedTab()
                .tabItem { Label("Avanzate", systemImage: "wrench.adjustable") }
        }
        .frame(width: 500, height: 400)
    }
}

struct GeneralTab: View {
    @Bindable var prefs: PreferencesStore

    var body: some View {
        Form {
            Section("Motore") {
                Picker("Servizio", selection: $prefs.serviceType) {
                    Text("Stub (test)").tag(ServiceType.stub)
                    Text("Locale (llama.cpp)").tag(ServiceType.local)
                    Text("Remoto (OpenAI)").tag(ServiceType.remote)
                    Text("Ollama").tag(ServiceType.ollama)
                    Text("OpenRouter").tag(ServiceType.openRouter)
                }

                if prefs.serviceType == .remote {
                    TextField("Base URL", text: $prefs.openAIBaseURL)
                    TextField("Modello", text: $prefs.openAIModel)
                }

                if prefs.serviceType == .ollama {
                    TextField("URL Ollama", text: $prefs.ollamaBaseURL)
                    TextField("Modello", text: $prefs.ollamaModel)
                }

                if prefs.serviceType == .openRouter {
                    SecureField("API Key OpenRouter", text: $prefs.openRouterAPIKey)
                    TextField("Modello (es. openai/gpt-4o-mini)", text: $prefs.openRouterModel)
                }
            }

            Section("Lingua") {
                Picker("Lingua", selection: $prefs.language) {
                    Text("Italiano").tag("it")
                    Text("English (US)").tag("en-US")
                    Text("English (UK)").tag("en-GB")
                    Text("Español").tag("es")
                    Text("Français").tag("fr")
                    Text("Deutsch").tag("de")
                    Text("中文").tag("zh")
                }

                Picker("Stile", selection: $prefs.style) {
                    Text("Equilibrato").tag("equilibrato")
                    Text("Formale").tag("formale")
                    Text("Informale").tag("informale")
                    Text("Accademico").tag("accademico")
                }
            }

            Section("Scorciatoie") {
                Toggle("Controllo automatico", isOn: $prefs.autoCheckEnabled)
                Text("Cmd+Shift+E — Controlla selezione").font(.caption).foregroundColor(.secondary)
                Text("Cmd+Shift+T — Controlla fluidità").font(.caption).foregroundColor(.secondary)
                Text("Cmd+Shift+F — Apri editor").font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ModelsTab: View {
    @Bindable var prefs: PreferencesStore

    var body: some View {
        Form {
            Section("Modello Locale") {
                TextField("ID Modello", text: $prefs.selectedModelID)
                Text("Esempio: qwen2.5-1.5b-instruct-q4_k_m")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

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
                    for idx in indexSet {
                        prefs.deleteCustomPrompt(prefs.customPrompts[idx])
                    }
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

struct AdvancedTab: View {
    var body: some View {
        Form {
            Section("Debug") {
                Text("Accessibilità: \(PreferencesStore.shared.isAccessibilityEnabled ? "OK" : "Non abilitata")")
                Text("Bundle: \(Constants.bundleID)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

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
                    for idx in indexSet {
                        prefs.deleteAppRule(prefs.appRules[idx])
                    }
                }
            }

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
            .padding()
        }
    }
}

struct ExclusionsTab: View {
    @Bindable var prefs: PreferencesStore

    var body: some View {
        VStack {
            List {
                ForEach(Array(prefs.excludedBundleIDs).sorted(), id: \.self) { bundleID in
                    HStack {
                        Text(bundleID)
                        Spacer()
                        Text("escluso")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onDelete { indexSet in
                    for idx in indexSet {
                        let id = Array(prefs.excludedBundleIDs).sorted()[idx]
                        prefs.removeExclusion(id)
                    }
                }
            }

            HStack {
                Button("Aggiungi app") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.application]
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.message = "Seleziona un'app da escludere dal controllo automatico"
                    if panel.runModal() == .OK,
                       let url = panel.url,
                       let bundle = Bundle(url: url),
                       let id = bundle.bundleIdentifier {
                        prefs.addExclusion(id)
                    }
                }
                Spacer()
            }
            .padding()
        }
    }
}
