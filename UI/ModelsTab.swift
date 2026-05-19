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
    @State private var externalModels: [DiscoveredModel] = []
    @State private var adoptedPaths: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Circle()
                    .fill(serverIsRunning ? Color.statusOk : Color.statusError)
                    .frame(width: 8, height: 8)
                Text(serverIsRunning ? "Server running" : "Server stopped")
                    .font(.caption)
                Spacer()
                if !externalModels.isEmpty {
                    Text("\(externalModels.count) found")
                        .font(.caption2)
                        .foregroundColor(.statusOk)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if let error = downloadError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.statusError)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.statusError)
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !externalModels.isEmpty {
                        Text("Models Found on this Mac")
                            .font(.headline)
                            .padding(.top, 8)
                        
                        ForEach(externalModels) { discovered in
                            ExternalModelRow(
                                model: discovered,
                                isAdopted: adoptedPaths.contains(discovered.path),
                                onAdopt: { adoptExternal(discovered) }
                            )
                        }
                        
                        Divider().padding(.vertical, 4)
                    }

                    Text("Available Models")
                        .font(.headline)
                        .padding(.top, 4)

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
                .padding()
            }
            .accessibilityElement(children: .contain)
        }
        // Footer toolbar: folder access + add file
        Divider()
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

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
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
            await ModelManager.shared.invalidateCache()
            await MainActor.run {
                adoptedPaths.insert(discovered.path)
                let name = discovered.name
                prefs.selectedModelID = name
                prefs.serviceType = .local
            }
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
        panel.allowedContentTypes = [.init(filenameExtension: "gguf")!]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a GGUF model file to add to Parrot"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await ModelManager.shared.adoptModel(path: url.path(percentEncoded: false))
            await ModelManager.shared.invalidateCache()
            let name = url.deletingPathExtension().lastPathComponent
            await MainActor.run {
                prefs.selectedModelID = name
                prefs.serviceType = .local
                externalModels = []  // trigger refresh
            }
            externalModels = await ModelManager.shared.discoverExternalModels()
            adoptedPaths = Set(ModelManager.shared.adoptedModelPaths())
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
        let completedFiles = files.filter { !$0.hasSuffix(".partial") }
        return Set(models.filter { model in
            completedFiles.contains { $0.contains(model.id) || model.id.hasSuffix($0.replacingOccurrences(of: ".gguf", with: "")) }
        }.map(\.id))
    }

    private func downloadModel(_ rec: ModelRecommendation) {
        isDownloading = true
        activeDownloadID = rec.id
        downloadProgress = 0
        downloadError = nil
        downloadStatus = "Downloading..."
        downloadTask?.cancel()
        downloadTask = Task {
            // Force-close any stalled URLSession from the previous download
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
                // Invalidate model path cache then start the server immediately
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
                Text("Downloaded")
                    .font(.caption)
                    .foregroundColor(.statusOk)
            } else {
                Button("Download") { onDownload() }
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
                .foregroundColor(.accentBrand)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label(model.source, systemImage: "folder")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                    Label(formatSize(model.size), systemImage: "doc")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                }
            }

            Spacer()

            if isAdopted {
                Text("In use")
                    .font(.caption)
                    .foregroundColor(.statusOk)
            } else {
                Button("Use") { onAdopt() }
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
