import SwiftUI

struct SettingsView: View {
    @State private var prefs = PreferencesStore.shared
    @State private var serverIsRunning = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab(prefs: prefs, serverIsRunning: serverIsRunning)
                .tabItem { Label("Generale", systemImage: "gearshape") }
                .tag(0)

            ModelsTab(prefs: prefs, serverIsRunning: serverIsRunning)
                .tabItem { Label("Modelli", systemImage: "brain") }
                .tag(1)

            PromptTab(prefs: prefs)
                .tabItem { Label("Prompt", systemImage: "text.quote") }
                .tag(2)

            AppRulesTab(prefs: prefs)
                .tabItem { Label("Regole App", systemImage: "apps.iphone") }
                .tag(3)

            ExclusionsTab(prefs: prefs)
                .tabItem { Label("Esclusioni", systemImage: "eye.slash") }
                .tag(4)

            AdvancedTab()
                .tabItem { Label("Avanzate", systemImage: "wrench.adjustable") }
                .tag(5)
        }
        .frame(minWidth: 500, minHeight: 400)
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
        .task {
            serverIsRunning = await ServerManager.shared.currentPort > 0
            let stream = AsyncStream<Void> { continuation in
                let task = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(3))
                        if Task.isCancelled { break }
                        continuation.yield(())
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
            for await _ in stream {
                guard selectedTab <= 1 else { continue }
                let running = await ServerManager.shared.currentPort > 0
                guard running != serverIsRunning else { continue }
                serverIsRunning = running
            }
        }
    }
}

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
                Text("Cmd+Shift+E — Controlla selezione").font(.caption).foregroundColor(.secondary)
                Text("Cmd+Shift+T — Controlla fluidita").font(.caption).foregroundColor(.secondary)
                Text("Cmd+Shift+F — Apri editor").font(.caption).foregroundColor(.secondary)
            }

            Section("Stato Server") {
                HStack {
                    Circle()
                        .fill(serverIsRunning ? Color.green : Color.red)
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

struct ModelsTab: View {
    @Bindable var prefs: PreferencesStore
    var serverIsRunning: Bool
    @State private var downloadProgress: Double = 0
    @State private var isDownloading = false
    @State private var downloadError: String?
    @State private var models: [ModelRecommendation] = []
    @State private var activeDownloadID: String?
    @State private var downloadTask: Task<Void, Never>?
    @State private var downloadStatus: String = ""
    @State private var downloadedModels: Set<String> = []
    @State private var externalModels: [DiscoveredModel] = []
    @State private var adoptedPaths: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Circle()
                    .fill(serverIsRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(serverIsRunning ? "Server attivo" : "Server fermo")
                    .font(.caption)
                Spacer()
                if !externalModels.isEmpty {
                    Text("\(externalModels.count) trovati")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            HStack {
                Circle()
                    .fill(serverIsRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(serverIsRunning ? "Server attivo" : "Server fermo")
                    .font(.caption)
                Spacer()
                if !externalModels.isEmpty {
                    Text("\(externalModels.count) trovati")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if let error = downloadError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }

            List {
                if !externalModels.isEmpty {
                    Section("Modelli Trovati sul Computer") {
                        ForEach(externalModels) { discovered in
                            ExternalModelRow(
                                model: discovered,
                                isAdopted: adoptedPaths.contains(discovered.path),
                                onAdopt: { adoptExternal(discovered) }
                            )
                        }
                    }
                }

                Section("Modelli Disponibili") {
                    ForEach(models, id: \.id) { model in
                        ModelRow(
                            model: model,
                            isDownloaded: downloadedModels.contains(model.id),
                            isDownloading: activeDownloadID == model.id,
                            progress: activeDownloadID == model.id ? downloadProgress : 0,
                            status: activeDownloadID == model.id ? downloadStatus : "",
                            onDownload: { downloadModel(model) }
                        )
                    }
                }
            }
            .listStyle(.inset)
        }
        .task {
            models = await ModelManager.shared.recommendedModels()
            downloadedModels = await detectDownloadedModels()
            externalModels = await ModelManager.shared.discoverExternalModels()
            adoptedPaths = Set(ModelManager.shared.adoptedModelPaths())
        }
        .onDisappear {
            downloadTask?.cancel()
        }
    }

    private func adoptExternal(_ discovered: DiscoveredModel) {
        Task {
            await ModelManager.shared.adoptModel(path: discovered.path)
            await MainActor.run {
                adoptedPaths.insert(discovered.path)
                let name = discovered.name
                prefs.selectedModelID = name
                prefs.serviceType = .local
            }
        }
    }

    private func detectDownloadedModels() async -> Set<String> {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("RefineClone/Models")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false)) else {
            return []
        }
        return Set(models.filter { model in
            files.contains { $0.contains(model.id) || model.id.hasSuffix($0.replacingOccurrences(of: ".gguf", with: "")) }
        }.map(\.id))
    }

    private func downloadModel(_ rec: ModelRecommendation) {
        isDownloading = true
        activeDownloadID = rec.id
        downloadProgress = 0
        downloadError = nil
        downloadStatus = "Download in corso..."
        downloadTask?.cancel()
        downloadTask = Task {
            do {
                let stream = ModelManager.shared.downloadModelWithProgress(
                    from: rec.url,
                    expectedSHA256: rec.expectedSHA256
                )
                for try await progress in stream {
                    guard !Task.isCancelled else { return }
                    switch progress {
                    case .downloading(let fraction):
                        downloadProgress = fraction
                        downloadStatus = "Download \(Int(fraction * 100))%"
                    case .verifying(let fraction):
                        downloadProgress = fraction
                        downloadStatus = "Verifica \(Int(fraction * 100))%"
                    case .complete:
                        downloadProgress = 1.0
                        downloadStatus = "Completato"
                    }
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    prefs.selectedModelID = rec.id
                    prefs.serviceType = .local
                    isDownloading = false
                    activeDownloadID = nil
                    downloadStatus = ""
                    downloadedModels.insert(rec.id)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    downloadError = error.localizedDescription
                    isDownloading = false
                    activeDownloadID = nil
                    downloadStatus = ""
                }
            }
        }
    }
}

private struct ModelRow: View {
    let model: ModelRecommendation
    let isDownloaded: Bool
    let isDownloading: Bool
    let progress: Double
    let status: String
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if isDownloaded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                    Text(model.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text(model.reason)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Label("~\(model.ramRequired)GB RAM", systemImage: "memorychip")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let warning = model.warning {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            if isDownloading {
                VStack(spacing: 2) {
                    ProgressView(value: progress)
                        .frame(width: 60)
                    Text(status)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else if isDownloaded {
                Text("Scaricato")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Button("Scarica") { onDownload() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ExternalModelRow: View {
    let model: DiscoveredModel
    let isAdopted: Bool
    let onAdopt: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.fill")
                .foregroundColor(.blue)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label(model.source, systemImage: "folder")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Label(formatSize(model.size), systemImage: "doc")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isAdopted {
                Text("In uso")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Button("Usa") { onAdopt() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatSize(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1.0 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
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
                    let toDelete = indexSet.map { prefs.customPrompts[$0] }
                    for prompt in toDelete {
                        prefs.deleteCustomPrompt(prompt)
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
    @State private var hfToken: String = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.hfToken) ?? ""
    @State private var tokenSaved = false

    var body: some View {
        Form {
            Section("HuggingFace") {
                HStack {
                    SecureField("Token HF (opzionale, per download veloci)", text: $hfToken)
                        .textFieldStyle(.roundedBorder)
                    Button("Salva") {
                        if hfToken.isEmpty {
                            UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.hfToken)
                        } else {
                            UserDefaults.standard.set(hfToken, forKey: Constants.UserDefaultsKey.hfToken)
                        }
                        tokenSaved = true
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            tokenSaved = false
                        }
                    }
                    .disabled(hfToken == UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.hfToken) ?? "")
                }
                if tokenSaved {
                    Text("Token salvato").font(.caption).foregroundColor(.green)
                }
                Text("Senza token: ~500 KB/s. Con token: fino a 50 MB/s.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Crea un token su huggingface.co/settings/tokens (tipo: Read)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

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
                    let toDelete = indexSet.map { prefs.appRules[$0] }
                    for rule in toDelete {
                        prefs.deleteAppRule(rule)
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
                    let toDelete = indexSet.map { Array(prefs.excludedBundleIDs).sorted()[$0] }
                    for id in toDelete {
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

private struct OpenRouterKeyField: View {
    let prefs: PreferencesStore
    @State private var localKey: String = ""

    var body: some View {
        SecureField("API Key OpenRouter", text: $localKey)
            .onAppear {
                localKey = prefs.openRouterAPIKey
            }
            .onSubmit {
                prefs.openRouterAPIKey = localKey
            }
            .onDisappear {
                prefs.openRouterAPIKey = localKey
            }
    }
}
