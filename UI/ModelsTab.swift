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
                Text(serverIsRunning ? "Server attivo" : "Server fermo")
                    .font(.caption)
                Spacer()
                if !externalModels.isEmpty {
                    Text("\(externalModels.count) trovati")
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
                        Text("Modelli Trovati sul Computer")
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

                    Text("Modelli Disponibili")
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
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return []
        }
        let dir = appSupport.appendingPathComponent("RefineClone/Models")
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
                Text("Scaricato")
                    .font(.caption)
                    .foregroundColor(.statusOk)
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
                Text("In uso")
                    .font(.caption)
                    .foregroundColor(.statusOk)
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
