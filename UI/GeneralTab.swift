import SwiftUI

struct GeneralTab: View {
    @Bindable var prefs: PreferencesStore
    var serverIsRunning: Bool

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
                    OpenAIKeyField(prefs: prefs)
                    TextField("Base URL", text: $prefs.openAIBaseURL)
                    TextField("Modello", text: $prefs.openAIModel)
                }

                if prefs.serviceType == .ollama {
                    TextField("URL Ollama", text: $prefs.ollamaBaseURL)
                    TextField("Modello", text: $prefs.ollamaModel)
                }

                if prefs.serviceType == .openRouter {
                    OpenRouterKeyField(prefs: prefs)
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
                Toggle("Controllo in tempo reale", isOn: $prefs.realtimeEnabled)
                    .disabled(!prefs.autoCheckEnabled)
                Text("Cmd+Shift+E — Controlla selezione").font(.caption).foregroundColor(.textSecondary)
                Text("Cmd+Shift+T — Controlla fluidita").font(.caption).foregroundColor(.textSecondary)
                Text("Cmd+Shift+F — Apri editor").font(.caption).foregroundColor(.textSecondary)
            }

            Section("Stato Server") {
                HStack {
                    Circle()
                        .fill(serverIsRunning ? Color.statusOk : Color.statusError)
                        .frame(width: 8, height: 8)
                    Text(serverIsRunning ? "llama-server: attivo" : "llama-server: fermo")
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct OpenAIKeyField: View {
    let prefs: PreferencesStore
    @State private var localKey: String = ""

    var body: some View {
        SecureField("API Key OpenAI", text: $localKey)
            .onAppear { localKey = prefs.openAIAPIKey }
            .onSubmit { prefs.openAIAPIKey = localKey }
            .onDisappear { prefs.openAIAPIKey = localKey }
    }
}

private struct OpenRouterKeyField: View {
    let prefs: PreferencesStore
    @State private var localKey: String = ""

    var body: some View {
        SecureField("API Key OpenRouter", text: $localKey)
            .onAppear { localKey = prefs.openRouterAPIKey }
            .onSubmit { prefs.openRouterAPIKey = localKey }
            .onDisappear { prefs.openRouterAPIKey = localKey }
    }
}
