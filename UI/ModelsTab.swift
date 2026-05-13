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

            List {
                if !externalModels.isEmpty {
                    Section("Modelli Trovati sul Computer") {
                        ForEach(externalModels) { discovered in
                            ExternalModelRow(
                                model: discovered,
                                isAdopted: adoptedPaths.contains(discovered.path),
                                onAdopt: { adoptedPaths.insert(discovered.path) }
                            )
                        }
                    }
                }

                Section("Modelli Consigliati") {
                    ForEach(models, id: \.id) { model in
                        ModelRow(
                            model: model,
                            isDownloaded: downloadedModels.contains(model.id),
                            isDownloading: activeDownloadID == model.id,
                            progress: downloadProgress,
                            status: downloadStatus,
                            onDownload: { }
                        )
                    }
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

    var body: some View { EmptyView() }
}

private struct ExternalModelRow: View {
    let model: DiscoveredModel
    let isAdopted: Bool
    let onAdopt: () -> Void

    var body: some View { EmptyView() }
}
