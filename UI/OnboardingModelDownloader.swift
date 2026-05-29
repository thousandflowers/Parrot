import SwiftUI

// MARK: - Inline Model Downloader (used in onboarding)

struct OnboardingModelDownloader: View {
    @State private var models: [ModelRecommendation] = []
    @State private var selectedIndex = 0
    @State private var isDownloading = false
    @State private var progress: Double = 0
    @State private var statusMessage = ""
    @State private var isComplete = false
    @State private var errorMessage: String?
    @State private var downloadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if models.isEmpty {
                ProgressView().scaleEffect(0.7).frame(maxWidth: .infinity, alignment: .leading)
            } else if isComplete {
                Label("Model ready to use", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.statusOk)
                    .font(.caption)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("", selection: $selectedIndex) {
                        ForEach(Array(models.enumerated()), id: \.offset) { idx, model in
                            Text(model.name + " - " + model.reason).tag(idx)
                        }
                    }
                    .labelsHidden()
                    .disabled(isDownloading)

                    if isDownloading {
                        ProgressView(value: progress)
                        Text(statusMessage)
                            .font(.caption2)
                            .foregroundStyle(Color.textSecondary)
                        Button("Cancel") {
                            downloadTask?.cancel()
                            downloadTask = nil
                            isDownloading = false
                            progress = 0
                            statusMessage = ""
                        }
                        .controlSize(.small)
                    } else {
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(Color.statusError)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 8) {
                            Button("Download now") { startDownload() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            Text("or download later from Settings → Models")
                                .font(.caption2)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }
        }
        .task {
            models = await ModelManager.shared.recommendedModels()
        }
    }

    private func startDownload() {
        guard !models.isEmpty else { return }
        let model = models[min(selectedIndex, models.count - 1)]
        isDownloading = true
        progress = 0
        statusMessage = "Starting download…"
        errorMessage = nil
        downloadTask = Task {
            do {
                let stream = ModelManager.shared.downloadModelWithProgress(from: model.url, expectedSHA256: model.expectedSHA256)
                for try await p in stream {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        switch p {
                        case .downloading(let f): progress = f; statusMessage = "Downloading \(Int(f * 100))%"
                        case .verifying(let f): progress = f; statusMessage = "Verifying \(Int(f * 100))%"
                        case .complete: progress = 1.0; statusMessage = "Complete"
                        }
                    }
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    PreferencesStore.shared.selectedModelID = model.id
                    PreferencesStore.shared.serviceType = .local
                    isDownloading = false
                    isComplete = true
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isDownloading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
