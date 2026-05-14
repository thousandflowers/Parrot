import SwiftUI

struct ModelsTab: View {
    @Bindable var prefs: PreferencesStore
    var serverIsRunning: Bool
    @State private var downloadProgress: Double = 0
    @State private var isDownloading = false
    @State private var downloadError: String?
    @State private var recommended: ModelRecommendation?
    @State private var downloadTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Modello Locale") {
                TextField("ID Modello", text: $prefs.selectedModelID)
                Text("Esempio: qwen2.5-1.5b-instruct-q4_k_m")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Modello Raccomandato") {
                if let rec = recommended {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(rec.name).font(.headline)
                        Text(rec.reason).font(.caption).foregroundColor(.secondary)
                        Text("RAM richiesta: ~\(rec.ramRequired) GB").font(.caption)

                        if let warning = rec.warning {
                            Text(warning).font(.caption).foregroundColor(.orange)
                        }

                        if isDownloading {
                            ProgressView(value: downloadProgress)
                            Text("\(Int(downloadProgress * 100))%")
                                .font(.caption)
                        } else {
                            Button("Scarica Modello") {
                                downloadRecommended(rec)
                            }
                            .disabled(isDownloading)
                        }
                    }
                }

                if let error = downloadError {
                    Text(error).foregroundColor(.red).font(.caption)
                }

                HStack {
                    Circle()
                        .fill(serverIsRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(serverIsRunning ? "Server attivo" : "Server fermo")
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            recommended = await ModelManager.shared.recommendedDefaultModel()
        }
        .onDisappear {
            downloadTask?.cancel()
        }
    }

    private func downloadRecommended(_ rec: ModelRecommendation) {
        isDownloading = true
        downloadProgress = 0
        downloadError = nil
        downloadTask?.cancel()
        downloadTask = Task {
            do {
                let destinationURL = try await ModelManager.shared.downloadModel(
                    from: rec.url,
                    expectedSHA256: rec.expectedSHA256
                )
                guard !Task.isCancelled else { return }
                let modelID = destinationURL.deletingPathExtension().lastPathComponent
                await MainActor.run {
                    prefs.selectedModelID = modelID
                    prefs.serviceType = .local
                    isDownloading = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    downloadError = error.localizedDescription
                    isDownloading = false
                }
            }
        }
    }
}
