import SwiftUI

private struct CatalogEntry: Identifiable {
    let id: String
    let displayName: String
    let url: URL
    let size: String
    let ramGB: Int
    let badge: String?
}

private let catalog: [CatalogEntry] = [
    .init(id: "Mistral-7B-Instruct-v0.3-Q4_K_M",
          displayName: "Mistral 7B Instruct v0.3",
          url: URL(string: "https://huggingface.co/bartowski/Mistral-7B-Instruct-v0.3-GGUF/resolve/main/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf")!,
          size: "~4.1 GB", ramGB: 5, badge: "16 GB+ · consigliato"),
    .init(id: "Phi-3.5-mini-instruct-Q4_K_M",
          displayName: "Phi 3.5 Mini Instruct (3.8B)",
          url: URL(string: "https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf")!,
          size: "~2.2 GB", ramGB: 4, badge: "8 GB+"),
    .init(id: "Llama-3.2-3B-Instruct-Q4_K_M",
          displayName: "Llama 3.2 — 3B Instruct",
          url: URL(string: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf")!,
          size: "~1.9 GB", ramGB: 3, badge: "leggero"),
    .init(id: "qwen2.5-7b-instruct-q4_k_m",
          displayName: "Qwen 2.5 — 7B Instruct",
          url: URL(string: "https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/main/qwen2.5-7b-instruct-q4_k_m.gguf")!,
          size: "~4.7 GB", ramGB: 6, badge: "ZH · multilingua"),
    .init(id: "qwen2.5-1.5b-instruct-q4_k_m",
          displayName: "Qwen 2.5 — 1.5B Instruct",
          url: URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!,
          size: "~1 GB", ramGB: 2, badge: "leggero · ZH"),
]

private let modelsDir: URL = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    .appendingPathComponent("RefineClone/Models")

struct ModelsTab: View {
    @Bindable var prefs: PreferencesStore
    var serverIsRunning: Bool

    // llama-server
    @State private var llamaServerFound = false
    @State private var brewFound = false
    @State private var isDownloadingServer = false
    @State private var serverDownloadProgress: Double = 0
    @State private var serverDownloadTask: Task<Void, Never>?
    @State private var serverDownloadError: String?

    // model — parallel downloads, keyed by taskID
    @State private var downloadedIDs: Set<String> = []
    @State private var downloadProgress: [String: Double] = [:]   // taskID -> progress
    @State private var downloadTasks: [String: Task<Void, Never>] = [:]  // taskID -> task
    @State private var downloadErrors: [String: String] = [:]     // taskID -> error
    @State private var customURL: String = ""

    var body: some View {
        Form {
            // ── llama-server ──────────────────────────────────────────────
            Section("llama-server (motore locale)") {
                if llamaServerFound {
                    HStack {
                        Label("llama-server installato", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.refineSuccess)
                        Spacer()
                        Button("Aggiorna") { refresh() }.controlSize(.small)
                    }
                    HStack {
                        Circle()
                            .fill(serverIsRunning ? Color.refineSuccess : Color.refineWarning)
                            .frame(width: 8, height: 8)
                        Text(serverIsRunning ? "Server attivo" : "Server fermo — si avvia automaticamente all'uso")
                            .font(.caption)
                    }
                } else {
                    Label("llama-server non trovato", systemImage: "xmark.circle.fill")
                        .foregroundColor(.refineError)
                    HStack {
                        Text("Richiesto per il servizio Locale. Puoi scaricarlo automaticamente o installarlo via Homebrew.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Aggiorna") { refresh() }.controlSize(.small)
                    }

                    if isDownloadingServer {
                        ProgressView()
                        Text("Installazione tramite Homebrew in corso (può richiedere qualche minuto)…")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Annulla") { serverDownloadTask?.cancel(); isDownloadingServer = false }
                            .controlSize(.small)
                    } else if brewFound {
                        Button("Installa llama-server via Homebrew") { downloadLlamaServer() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Text("Homebrew non trovato. Installa prima Homebrew, poi esegui nel Terminale:")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("brew install llama.cpp")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    if let err = serverDownloadError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.refineError)
                                .font(.system(size: 12))
                                .accessibilityHidden(true)
                            Text(err)
                                .foregroundColor(.refineError)
                                .font(.caption)
                            Spacer()
                            Button("Riprova") { downloadLlamaServer() }
                                .controlSize(.small)
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }

            // ── Modello attivo ────────────────────────────────────────────
            Section("Modello locale attivo") {
                if downloadedIDs.isEmpty {
                    Text("Nessun modello scaricato. Scarica un modello dal catalogo qui sotto.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("Modello", selection: $prefs.selectedModelID) {
                        ForEach(Array(downloadedIDs).sorted(), id: \.self) { id in
                            Text(id).tag(id)
                        }
                    }
                }
            }

            // ── Catalogo ──────────────────────────────────────────────────
            Section("Catalogo modelli") {
                ForEach(catalog) { entry in
                    CatalogRow(
                        entry: entry,
                        isDownloaded: downloadedIDs.contains(entry.id),
                        isSelected: prefs.selectedModelID == entry.id,
                        downloadProgress: downloadProgress[entry.id],
                        downloadError: downloadErrors[entry.id],
                        onDownload: { startModelDownload(url: entry.url, modelID: entry.id, taskID: entry.id) },
                        onCancel: { cancelDownload(taskID: entry.id) },
                        onSelect: { prefs.selectedModelID = entry.id },
                        onDelete: { deleteModel(id: entry.id) }
                    )
                }
            }

            // ── URL personalizzato ────────────────────────────────────────
            Section("URL personalizzato") {
                TextField("https://huggingface.co/.../model.gguf", text: $customURL)
                    .autocorrectionDisabled()
                let customProgress = downloadProgress["_custom"]
                if let p = customProgress {
                    ProgressRowView(progress: p)
                    HStack {
                        Spacer()
                        Button("Annulla") { cancelDownload(taskID: "_custom") }
                            .controlSize(.small)
                    }
                } else {
                    Button("Scarica da URL") { downloadFromCustomURL() }
                        .disabled(customURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let err = downloadErrors["_custom"] {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.refineError)
                            .font(.system(size: 12))
                            .accessibilityHidden(true)
                        Text(err)
                            .foregroundColor(.refineError)
                            .font(.caption)
                        Spacer()
                        Button("Riprova") { downloadFromCustomURL() }
                            .controlSize(.small)
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { refresh() }
        .onDisappear {
            downloadTasks.values.forEach { $0.cancel() }
            serverDownloadTask?.cancel()
        }
    }

    // MARK: - Helpers

    private func refresh() {
        llamaServerFound = ModelManager.shared.resolvedLlamaServerURL() != nil
        brewFound = ModelManager.shared.resolvedBrewPath() != nil
        let contents = (try? FileManager.default.contentsOfDirectory(
            atPath: modelsDir.path(percentEncoded: false))) ?? []
        downloadedIDs = Set(contents.filter { $0.hasSuffix(".gguf") }.map { String($0.dropLast(5)) })
    }

    // MARK: - llama-server download

    private func downloadLlamaServer() {
        serverDownloadTask?.cancel()
        serverDownloadError = nil
        isDownloadingServer = true
        serverDownloadProgress = 0

        serverDownloadTask = Task {
            do {
                let stream = await ModelManager.shared.downloadLlamaServerWithProgress()
                for try await progress in stream {
                    guard !Task.isCancelled else { return }
                    await MainActor.run { serverDownloadProgress = progress }
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isDownloadingServer = false
                    refresh()
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    serverDownloadError = error.localizedDescription
                    isDownloadingServer = false
                }
            }
        }
    }

    // MARK: - Model download

    private func downloadFromCustomURL() {
        let str = customURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: str) else {
            downloadErrors["_custom"] = "URL non valido"
            return
        }
        let id = url.deletingPathExtension().lastPathComponent
        startModelDownload(url: url, modelID: id, taskID: "_custom")
    }

    private func cancelDownload(taskID: String) {
        downloadTasks[taskID]?.cancel()
        downloadTasks.removeValue(forKey: taskID)
        downloadProgress.removeValue(forKey: taskID)
    }

    private func startModelDownload(url: URL, modelID: String, taskID: String) {
        cancelDownload(taskID: taskID)
        downloadErrors.removeValue(forKey: taskID)
        downloadProgress[taskID] = 0

        let task = Task {
            do {
                let stream = await ModelManager.shared.downloadModelWithProgress(from: url)
                for try await progress in stream {
                    guard !Task.isCancelled else { return }
                    await MainActor.run { downloadProgress[taskID] = progress }
                }
                guard !Task.isCancelled else { return }
                await autoSetupAfterDownload(modelID: modelID, taskID: taskID)
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    downloadErrors[taskID] = error.localizedDescription
                    downloadProgress.removeValue(forKey: taskID)
                    downloadTasks.removeValue(forKey: taskID)
                }
            }
        }
        downloadTasks[taskID] = task
    }

    @MainActor
    private func autoSetupAfterDownload(modelID: String, taskID: String) async {
        downloadProgress.removeValue(forKey: taskID)
        downloadTasks.removeValue(forKey: taskID)
        prefs.selectedModelID = modelID
        refresh()

        guard ModelManager.shared.resolvedLlamaServerURL() != nil else {
            downloadErrors[taskID] = "Modello scaricato. Installa llama.cpp per usare il servizio Locale (vedi sezione sopra)."
            return
        }
        prefs.serviceType = .local
        prefs.fluencyServiceType = .local

        guard let modelPath = ModelManager.shared.currentModelPath else { return }
        await ServerManager.shared.stop()
        try? await ServerManager.shared.start(modelPath: modelPath)
    }

    private func deleteModel(id: String) {
        let path = modelsDir.appendingPathComponent("\(id).gguf")
        try? FileManager.default.removeItem(at: path)
        refresh()
        if prefs.selectedModelID == id {
            prefs.selectedModelID = downloadedIDs.first ?? ""
        }
    }
}

// MARK: - Progress row helper

private struct ProgressRowView: View {
    let progress: Double
    var body: some View {
        if progress > 0 && progress <= 1 {
            ProgressView(value: progress)
            Text("\(Int(progress * 100))%").font(.caption2).foregroundStyle(.secondary)
        } else if progress < 0 {
            ProgressView()
            let mb = Int(-progress / 1_000_000)
            Text(mb > 0 ? "\(mb) MB ricevuti…" : "Download in corso…")
                .font(.caption2).foregroundStyle(.secondary)
        } else {
            ProgressView()
            Text("Connessione…").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Catalog row

private struct CatalogRow: View {
    let entry: CatalogEntry
    let isDownloaded: Bool
    let isSelected: Bool
    let downloadProgress: Double?   // nil = not downloading
    let downloadError: String?
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onSelect: () -> Void
    let onDelete: () -> Void

    var isDownloading: Bool { downloadProgress != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry.displayName)
                            .font(.system(size: 13, weight: .medium))
                        if isSelected {
                            Text("attivo")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.refineSuccess.opacity(0.25)))
                                .foregroundColor(.refineSuccess)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    HStack(spacing: 8) {
                        Text(entry.size).font(.caption).foregroundStyle(.secondary)
                        Text("RAM: ~\(entry.ramGB) GB").font(.caption).foregroundStyle(.secondary)
                        if let badge = entry.badge {
                            Text(badge)
                                .font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                Spacer()
                if isDownloading {
                    Button("Annulla") { onCancel() }
                        .controlSize(.small)
                        .foregroundColor(.refineError)
                        .accessibilityLabel("Annulla download di \(entry.displayName)")
                } else if isDownloaded {
                    if !isSelected {
                        Button("Usa") { onSelect() }
                            .controlSize(.small)
                            .accessibilityLabel("Usa modello \(entry.displayName)")
                    }
                    Button("Elimina") { onDelete() }
                        .controlSize(.small)
                        .foregroundColor(.refineError)
                        .accessibilityLabel("Elimina modello \(entry.displayName)")
                } else {
                    Button("Scarica") { onDownload() }
                        .controlSize(.small)
                        .accessibilityLabel("Scarica modello \(entry.displayName)")
                }
            }
            if let p = downloadProgress {
                ProgressRowView(progress: p)
            }
            if let err = downloadError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.refineError)
                        .font(.system(size: 12))
                        .accessibilityHidden(true)
                    Text(err)
                        .foregroundColor(.refineError)
                        .font(.caption2)
                    Spacer()
                    Button("Riprova") { onDownload() }
                        .controlSize(.small)
                        .foregroundColor(.accentColor)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
