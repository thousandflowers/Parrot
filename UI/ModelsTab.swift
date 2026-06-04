import SwiftUI

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
    @State private var localModels: [DiscoveredModel] = []

    var body: some View {
        Form {
            Section {
                Picker("Service", selection: $prefs.serviceType) {
                    Text("Apple Intelligence").tag(ServiceType.appleIntelligence)
                    Text("Local (llama.cpp)").tag(ServiceType.local)
                    Text("Ollama").tag(ServiceType.ollama)
                    Text("OpenAI / Compatible").tag(ServiceType.remote)
                    Text("OpenRouter").tag(ServiceType.openRouter)
                    Text("Stub (test)").tag(ServiceType.stub)
                }

                if prefs.serviceType == .appleIntelligence {
                    if #available(macOS 26.0, *) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(
                                AppleIntelligenceService.shared.isAvailable ? "Apple Intelligence ready" : "Apple Intelligence not available",
                                systemImage: AppleIntelligenceService.shared.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(AppleIntelligenceService.shared.isAvailable ? Color.statusOk : Color.statusWarning)
                            .font(.callout)
                            if !AppleIntelligenceService.shared.isAvailable {
                                Text(AppleIntelligenceService.shared.availabilityDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        Label("Apple Intelligence requires macOS 26", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.statusWarning)
                            .font(.callout)
                    }
                }

                if prefs.serviceType == .remote {
                    OpenAIKeyField(prefs: prefs)
                    TextField("Base URL", text: $prefs.openAIBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Base URL")
                    TextField("Model", text: $prefs.openAIModel)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Model")
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Backup model (if primary fails)", text: $prefs.fallbackOpenAIModel)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Backup model")
                        Text("Optional. Used automatically when the primary model returns an error.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if prefs.serviceType == .ollama {
                    TextField("Ollama URL", text: $prefs.ollamaBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Ollama URL")
                    TextField("Model", text: $prefs.ollamaModel)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Ollama model")
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Backup model (if primary fails)", text: $prefs.fallbackOllamaModel)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Ollama backup model")
                        Text("Optional. Used automatically when the primary model returns an error.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if prefs.serviceType == .openRouter {
                    OpenRouterKeyField(prefs: prefs)
                    TextField("Model (e.g. openai/gpt-4o-mini)", text: $prefs.openRouterModel)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("OpenRouter model")
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Backup model (if primary fails)", text: $prefs.fallbackOpenRouterModel)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("OpenRouter backup model")
                        Text("Optional. Used automatically when the primary model returns an error.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label("AI Engine", systemImage: "cpu")
            }

            Section {
                if prefs.serviceType == .local {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(serverIsRunning ? Color.statusOk : Color.statusError)
                            .frame(width: 8, height: 8)
                        Text(serverIsRunning ? "llama-server running" : "llama-server not running")
                            .font(.callout)
                    }
                    if !serverIsRunning {
                        Text("The local server is not running. Check the configuration below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if prefs.serviceType == .appleIntelligence {
                    if #available(macOS 26.0, *) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(AppleIntelligenceService.shared.isAvailable ? Color.statusOk : Color.statusWarning)
                                .frame(width: 8, height: 8)
                            Text(AppleIntelligenceService.shared.isAvailable ? "Apple Intelligence ready" : "Apple Intelligence not available")
                                .font(.callout)
                        }
                        if !AppleIntelligenceService.shared.isAvailable {
                            Text(AppleIntelligenceService.shared.availabilityDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Circle().fill(Color.statusWarning).frame(width: 8, height: 8)
                            Text("Apple Intelligence requires macOS 26").font(.callout)
                        }
                    }
                }
            } header: {
                Label("Status", systemImage: "antenna.radiowaves.left.and.right")
            }

            if prefs.serviceType == .local {
                LlamaInstallerSection()
            }

            Section {
                Toggle("Auto-check", isOn: $prefs.autoCheckEnabled)
                Toggle("Real-time check", isOn: $prefs.realtimeEnabled)
            } header: {
                Label("Behavior", systemImage: "bolt")
            }

            if prefs.serviceType == .local {
                Section {
                    if let error = downloadError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.statusError)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.statusError)
                        }
                        .padding(.vertical, 2)
                    }

                    ForEach(models, id: \.id) { model in
                        ModelRow(
                            model: model,
                            isDownloaded: downloadedModels.contains(model.id),
                            isSelected: prefs.selectedModelID.lowercased() == model.id.lowercased(),
                            isDownloading: activeDownloadID == model.id,
                            progress: activeDownloadID == model.id ? downloadProgress : 0,
                            status: activeDownloadID == model.id ? downloadStatus : "",
                            onDownload: { downloadModel(model) },
                            onSelect: { selectModel(model) },
                            onDelete: { deleteModel($0) }
                        )
                    }
                } header: {
                    Label("Models", systemImage: "brain")
                } footer: {
                    HStack(spacing: 8) {
                        Button(action: openModelsFolder) {
                            Label("Open Models Folder", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Opens ~/Library/Application Support/Parrot/Models/ — drop .gguf files here")

                        Button(action: addModelFromFile) {
                            Label("Add from file…", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Pick any .gguf file from anywhere on your Mac")
                    }
                    .padding(.top, 4)
                }
            }

            if prefs.serviceType == .local && !uncatalogedLocalModels.isEmpty {
                Section {
                    ForEach(uncatalogedLocalModels) { model in
                        LocalModelRow(
                            model: model,
                            isSelected: prefs.selectedModelID.lowercased() == model.id.lowercased(),
                            onSelect: { selectLocalModel(model) },
                            onDelete: { deleteLocalModel($0) }
                        )
                    }
                } header: {
                    Label("Custom Models", systemImage: "doc.badge.plus")
                }
            }

            if prefs.serviceType == .local {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Backup model (if primary fails)", text: $prefs.fallbackLocalModelID)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Fallback model")
                        Text("Optional. If the selected model fails to load, Parrot will try this one instead. Enter a model ID from the list above.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("Fallback", systemImage: "arrow.triangle.swap")
                }
            }


        }
        .formStyle(.grouped)
        .scrollIndicators(.hidden)
        .frame(minHeight: 640, maxHeight: .infinity)
        .task {
            models = await ModelManager.shared.recommendedModels()
            localModels = await ModelManager.shared.localModels()
            downloadedModels = await detectDownloadedModels()
        }
        .onDisappear {
            downloadTask?.cancel()
        }
    }

    private var uncatalogedLocalModels: [DiscoveredModel] {
        localModels.filter { local in
            !models.contains { catalog in catalog.id.lowercased() == local.id.lowercased() }
        }
    }

    private func selectModel(_ rec: ModelRecommendation) {
        prefs.selectedModelID = rec.id
        prefs.serviceType = .local
        Task {
            async let stop: Void = ServerManager.shared.stop()
            async let invalidate: Void = ModelManager.shared.invalidateCache()
            _ = await (stop, invalidate)
            guard !Task.isCancelled else { return }
            await LocalLLMService.shared.warmup()
        }
    }

    private func selectLocalModel(_ model: DiscoveredModel) {
        prefs.selectedModelID = model.id
        prefs.serviceType = .local
        Task {
            async let stop: Void = ServerManager.shared.stop()
            async let invalidate: Void = ModelManager.shared.invalidateCache()
            _ = await (stop, invalidate)
            guard !Task.isCancelled else { return }
            await LocalLLMService.shared.warmup()
        }
    }

    private func openModelsFolder() {
        let path = ModelManager.shared.modelsDirPath
        try? FileManager.default.createDirectory(atPath: path,
                                                 withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func addModelFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "gguf") ?? .data]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a GGUF model file to add to Parrot"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await ModelManager.shared.adoptModel(path: url.path(percentEncoded: false))
            await ModelManager.shared.invalidateCache()
            let name = url.deletingPathExtension().lastPathComponent
            guard !Task.isCancelled else { return }
            await MainActor.run {
                prefs.selectedModelID = name
                prefs.serviceType = .local
            }
            await LocalLLMService.shared.warmup()
        }
    }

    private func detectDownloadedModels() async -> Set<String> {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return []
        }
        let dir = appSupport.appendingPathComponent("Parrot/Models")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false)) else {
            return []
        }
        let completedFiles = files.filter { $0.hasSuffix(".gguf") }
        return Set(models.filter { model in
            completedFiles.contains { file in
                file.localizedCaseInsensitiveContains(model.id) ||
                model.id.localizedCaseInsensitiveCompare(file.replacingOccurrences(of: ".gguf", with: "")) == .orderedSame
            }
        }.map(\.id))
    }

    private func deleteModel(_ id: String) {
        Task {
            await ModelManager.shared.removeModel(id: id)
            downloadedModels.remove(id)
            localModels = await ModelManager.shared.localModels()
        }
    }

    private func deleteLocalModel(_ model: DiscoveredModel) {
        Task {
            await ModelManager.shared.removeLocalModel(model)
            localModels = await ModelManager.shared.localModels()
        }
    }

    private func downloadModel(_ rec: ModelRecommendation) {
        isDownloading = true
        activeDownloadID = rec.id
        downloadProgress = 0
        downloadError = nil
        downloadStatus = "Downloading..."
        downloadTask?.cancel()
        downloadTask = Task {
            await ModelManager.shared.cancelActiveDownload()

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
                        downloadStatus = "Verifying \(Int(fraction * 100))%"
                    case .complete:
                        downloadProgress = 1.0
                        downloadStatus = "Complete"
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
                await ModelManager.shared.invalidateCache()
                await LocalLLMService.shared.warmup()
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
    let isSelected: Bool
    let isDownloading: Bool
    let progress: Double
    let status: String
    let onDownload: () -> Void
    let onSelect: () -> Void
    let onDelete: (String) -> Void

    @State private var showDeleteAlert = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if isDownloaded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.statusOk)
                            .font(.caption)
                    }
                    Text(model.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text(model.reason)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Label("~\(model.ramRequired)GB RAM", systemImage: "memorychip")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                    if let warning = model.warning {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundColor(.statusWarning)
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
                        .foregroundColor(.textSecondary)
                }
            } else if isDownloaded {
                HStack(spacing: 6) {
                    if isSelected {
                        Text("In use")
                            .font(.caption)
                            .foregroundColor(.statusOk)
                    } else {
                        Button("Use") { onSelect() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .accessibilityLabel("Use \(model.name)")
                    }
                    Button(action: { showDeleteAlert = true }) {
                        Image(systemName: "trash")
                            .foregroundColor(.statusError)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .accessibilityLabel("Delete \(model.name)")
                }
            } else {
                Button("Download") { onDownload() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel("Download \(model.name)")
            }
        }
        .padding(.vertical, 4)
        .alert("Delete model?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete(model.id)
            }
        } message: {
            Text("Delete the file for \"\(model.name)\"? This cannot be undone.")
        }
    }
}

// MARK: - Local (Custom) Model Row

private struct LocalModelRow: View {
    let model: DiscoveredModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: (DiscoveredModel) -> Void

    @State private var showDeleteAlert = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(formattedSize(model.size))
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            Spacer()
            HStack(spacing: 6) {
                if isSelected {
                    Text("In use")
                        .font(.caption)
                        .foregroundColor(.statusOk)
                } else {
                    Button("Use") { onSelect() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityLabel("Use \(model.name)")
                }
                Button(action: { showDeleteAlert = true }) {
                    Image(systemName: "trash")
                        .foregroundColor(.statusError)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("Delete \(model.name)")
            }
        }
        .padding(.vertical, 4)
        .alert("Delete model?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete(model)
            }
        } message: {
            Text("Delete the file for \"\(model.name)\"? This cannot be undone.")
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - llama-server Installer

private struct LlamaInstallerSection: View {
    private var installer: LlamaInstaller { LlamaInstaller.shared }

    var body: some View {
        switch installer.phase {
        case .unknown:
            EmptyView()
                .onAppear { installer.checkAvailability() }

        case .available:
            EmptyView()

        case .unavailable:
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("llama-server not found", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.statusWarning)
                        .font(.callout.weight(.medium))
                    Text("The local AI engine is not installed. Parrot can install it automatically via Homebrew, or download a prebuilt binary from GitHub.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Install llama-server") { installer.install() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityLabel("Install llama-server")
                }
                .padding(.vertical, 2)
            } header: {
                Label("Engine Setup", systemImage: "wrench.and.screwdriver")
            }

        case .installing(let progress, let message):
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.callout)
                    if progress < 0 {
                        ProgressView()
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                    }
                    Text("Do not close the app while installing.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } header: {
                Label("Engine Setup", systemImage: "wrench.and.screwdriver")
            }

        case .failed(let message):
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Installation failed", systemImage: "xmark.circle.fill")
                        .foregroundStyle(Color.statusError)
                        .font(.callout.weight(.medium))
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Try Again") { installer.install() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .accessibilityLabel("Try Again")
                        Button("Install Homebrew first…") {
                            guard let url = URL(string: "https://brew.sh") else { return }
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Install Homebrew first")
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Label("Engine Setup", systemImage: "wrench.and.screwdriver")
            }
        }
    }
}

// MARK: - Key Fields

private struct OpenAIKeyField: View {
    let prefs: PreferencesStore
    @State private var localKey: String = ""

    var body: some View {
        SecureField("API Key OpenAI", text: $localKey)
            .onAppear { localKey = prefs.openAIAPIKey }
            .onSubmit { prefs.openAIAPIKey = localKey }
            .onDisappear { prefs.openAIAPIKey = localKey }
            .accessibilityLabel("OpenAI API Key")
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
            .accessibilityLabel("OpenRouter API Key")
    }
}

#Preview {
    ModelsTab(prefs: PreferencesStore.shared, serverIsRunning: false)
}
