import SwiftUI

struct GeneralTab: View {
    @Bindable var prefs: PreferencesStore
    var serverIsRunning: Bool

    var body: some View {
        Form {
            Section("Correttore (Cmd+Shift+E)") {
                Picker("Servizio", selection: $prefs.serviceType) {
                    Text("Stub (test)").tag(ServiceType.stub)
                    Text("Locale (llama.cpp)").tag(ServiceType.local)
                    Text("Remoto (OpenAI)").tag(ServiceType.remote)
                    Text("Ollama").tag(ServiceType.ollama)
                    Text("OpenRouter").tag(ServiceType.openRouter)
                }

                if prefs.serviceType == .stub {
                    Label("Stub: restituisce testo finto. Vai su \"Modelli\" per scaricare un modello locale.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.refineWarning)
                }
            }

            Section("Fluency (Cmd+Shift+T)") {
                Picker("Servizio Fluency", selection: $prefs.fluencyServiceType) {
                    Text("Stub (test)").tag(ServiceType.stub)
                    Text("Locale (llama.cpp)").tag(ServiceType.local)
                    Text("Remoto (OpenAI)").tag(ServiceType.remote)
                    Text("Ollama").tag(ServiceType.ollama)
                    Text("OpenRouter").tag(ServiceType.openRouter)
                }

                if prefs.fluencyServiceType == .stub {
                    Label("Stub: restituisce testo finto.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.refineWarning)
                }
            }

            Section("Grammar — override servizio") {
                Picker("Servizio Grammar", selection: $prefs.grammarServiceType) {
                    Text("Predefinito (uguale a Correttore)").tag(ServiceType.stub)
                    Text("Locale (llama.cpp)").tag(ServiceType.local)
                    Text("Remoto (OpenAI)").tag(ServiceType.remote)
                    Text("Ollama").tag(ServiceType.ollama)
                    Text("OpenRouter").tag(ServiceType.openRouter)
                }
            }

            Section("Spiegazione") {
                Picker("Servizio Explain", selection: $prefs.explainServiceType) {
                    Text("Stub (test)").tag(ServiceType.stub)
                    Text("Locale (llama.cpp)").tag(ServiceType.local)
                    Text("Remoto (OpenAI)").tag(ServiceType.remote)
                    Text("Ollama").tag(ServiceType.ollama)
                    Text("OpenRouter").tag(ServiceType.openRouter)
                }
            }

            let usesRemote = prefs.serviceType == .remote || prefs.fluencyServiceType == .remote
            let usesOllama = prefs.serviceType == .ollama || prefs.fluencyServiceType == .ollama
            let usesOpenRouter = prefs.serviceType == .openRouter || prefs.fluencyServiceType == .openRouter

            if usesRemote {
                Section("Configurazione OpenAI / Remoto") {
                    TextField("Base URL", text: $prefs.openAIBaseURL)
                    TextField("Modello", text: $prefs.openAIModel)
                }
            }

            if usesOllama {
                Section("Configurazione Ollama") {
                    TextField("URL Ollama", text: $prefs.ollamaBaseURL)
                    TextField("Modello", text: $prefs.ollamaModel)
                }
            }

            if usesOpenRouter {
                Section("Configurazione OpenRouter") {
                    OpenRouterKeyField(prefs: prefs)
                    TextField("Modello (es. openai/gpt-4o-mini)", text: $prefs.openRouterModel)
                }
            }

            Section("Lingua") {
                Picker("Lingua", selection: $prefs.language) {
                    Text(String(localized: "prefs.language.auto")).tag("auto")
                    Divider()
                    Text("Europee").font(.caption).foregroundStyle(.secondary).disabled(true)
                    Text("Italiano").tag("it")
                    Text("English (US)").tag("en-US")
                    Text("English (UK)").tag("en-GB")
                    Text("Español").tag("es")
                    Text("Français").tag("fr")
                    Text("Deutsch").tag("de")
                    Text("Português").tag("pt")
                    Text("Nederlands").tag("nl")
                    Text("Polski").tag("pl")
                    Text("Română").tag("ro")
                    Text("Svenska").tag("sv")
                    Text("Dansk").tag("da")
                    Text("Norsk").tag("no")
                    Text("Suomi").tag("fi")
                    Text("Čeština").tag("cs")
                    Text("Slovenčina").tag("sk")
                    Text("Magyar").tag("hu")
                    Text("Ελληνικά").tag("el")
                    Text("Български").tag("bg")
                    Text("Hrvatski").tag("hr")
                    Text("Srpski").tag("sr")
                    Text("Slovenščina").tag("sl")
                    Text("Eesti").tag("et")
                    Text("Latviešu").tag("lv")
                    Text("Lietuvių").tag("lt")
                    Text("Català").tag("ca")
                    Text("Galego").tag("gl")
                    Text("Euskara").tag("eu")
                    Text("Italiano (Svizzera)").tag("it-CH")
                    Divider()
                    Text("Mediorientali").font(.caption).foregroundStyle(.secondary).disabled(true)
                    Text("العربية").tag("ar")
                    Text("עברית").tag("he")
                    Text("فارسی").tag("fa")
                    Text("Türkçe").tag("tr")
                    Text("اردو").tag("ur")
                    Divider()
                    Text("Asiatiche").font(.caption).foregroundStyle(.secondary).disabled(true)
                    Text("中文").tag("zh")
                    Text("日本語").tag("ja")
                    Text("한국어").tag("ko")
                    Text("Tiếng Việt").tag("vi")
                    Text("ภาษาไทย").tag("th")
                    Text("Bahasa Indonesia").tag("id")
                    Text("Bahasa Melayu").tag("ms")
                    Text("Filipino").tag("fil")
                    Text("हिन्दी").tag("hi")
                    Text("বাংলা").tag("bn")
                    Text("தமிழ்").tag("ta")
                    Text("తెలుగు").tag("te")
                    Text("മലയാളം").tag("ml")
                    Text("ಕನ್ನಡ").tag("kn")
                    Text("ગુજરાતી").tag("gu")
                    Text("मराठी").tag("mr")
                    Divider()
                    Text("Altre").font(.caption).foregroundStyle(.secondary).disabled(true)
                    Text("Русский").tag("ru")
                    Text("Українська").tag("uk")
                    Text("Беларуская").tag("be")
                    Text("Қазақша").tag("kk")
                    Text("Azərbaycan").tag("az")
                    Text("Gaeilge").tag("ga")
                    Text("Íslenska").tag("is")
                    Text("Soomaaliga").tag("so")
                    Text("Swahili").tag("sw")
                    Text("Afrikaans").tag("af")
                    Text("Zulu").tag("zu")
                    Text("Latin").tag("la")
                    Text("Esperanto").tag("eo")
                }

                Picker("Stile", selection: $prefs.style) {
                    Text("Equilibrato").tag("equilibrato")
                    Text("Formale").tag("formale")
                    Text("Informale").tag("informale")
                    Text("Accademico").tag("accademico")
                }

                Picker("Lingua destinazione traduzione", selection: $prefs.translationLanguage) {
                    Text("Italiano").tag("it")
                    Text("English").tag("en")
                    Text("Español").tag("es")
                    Text("Français").tag("fr")
                    Text("Deutsch").tag("de")
                    Text("中文").tag("zh")
                    Text("日本語").tag("ja")
                    Text("العربية").tag("ar")
                    Text("Português").tag("pt")
                    Text("Русский").tag("ru")
                }
            }

            Section("Scorciatoie") {
                Toggle("Lightweight mode (forza modello ≤1.5B)", isOn: $prefs.lightweightMode)
                    .help("Riduce il consumo RAM a ~1GB. Richiede un modello 1.5B scaricato.")
                Toggle("Controllo in tempo reale", isOn: $prefs.realtimeEnabled)
                Text("Cmd+Shift+E — Correggi selezione").font(.caption).foregroundStyle(.secondary)
                Text("Cmd+Shift+A — Correggi e applica subito").font(.caption).foregroundStyle(.secondary)
                Text("Cmd+Shift+C — Writing Coach (analisi)").font(.caption).foregroundStyle(.secondary)
                Text("Cmd+Shift+T — Analisi fluency").font(.caption).foregroundStyle(.secondary)
                Text("Cmd+Shift+F — Apri editor flottante").font(.caption).foregroundStyle(.secondary)
                Text("Cmd+Shift+R — Correggi e sostituisci (senza pannello)").font(.caption).foregroundStyle(.secondary)
                Text("Cmd+Shift+Y — Traduci selezione").font(.caption).foregroundStyle(.secondary)
            }

            Section("Stato Server") {
                HStack {
                    Circle()
                        .fill(serverIsRunning ? Color.refineSuccess : Color.refineError)
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

private struct OpenRouterKeyField: View {
    let prefs: PreferencesStore
    @State private var localKey: String = ""
    @State private var isSaved = false

    var body: some View {
        HStack {
            SecureField("API Key OpenRouter", text: $localKey)
                .onAppear {
                    localKey = prefs.openRouterAPIKey
                    isSaved = !localKey.isEmpty
                }
                .onChange(of: localKey) { isSaved = false }
                .onSubmit { saveKey() }
                .onDisappear { saveKey() }
            if isSaved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.refineSuccess)
                    .accessibilityLabel("Chiave salvata")
            } else if !localKey.isEmpty {
                Image(systemName: "return.left")
                    .foregroundStyle(.secondary)
                    .help("Premi Invio per salvare")
                    .accessibilityHidden(true)
            }
        }
    }

    private func saveKey() {
        prefs.openRouterAPIKey = localKey
        isSaved = !localKey.isEmpty && prefs.openRouterAPIKey == localKey
    }
}
