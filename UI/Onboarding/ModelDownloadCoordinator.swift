import SwiftUI

/// Owns the Wren onboarding background model download so progress survives step changes.
/// Injectable `streamProvider` keeps it unit-testable without real network.
@MainActor
@Observable
final class ModelDownloadCoordinator {
    enum Phase: Equatable { case idle, downloading, verifying, complete, failed(String) }

    private(set) var phase: Phase = .idle
    private(set) var progress: Double = 0
    private(set) var statusMessage: String = ""

    typealias StreamProvider = (URL, String?) -> AsyncThrowingStream<DownloadProgress, Error>
    private let streamProvider: StreamProvider
    private let onComplete: (String) -> Void   // modelID
    private var task: Task<Void, Never>?

    init(streamProvider: @escaping StreamProvider = { url, sha in
            ModelManager.shared.downloadModelWithProgress(from: url, expectedSHA256: sha)
         },
         onComplete: @escaping (String) -> Void) {
        self.streamProvider = streamProvider
        self.onComplete = onComplete
    }

    var isFinished: Bool { phase == .complete }

    func start(modelID: String, url: URL, sha: String?) async {
        guard phase != .complete, phase != .downloading, phase != .verifying else { return }
        phase = .downloading
        progress = 0
        statusMessage = "Starting download…"
        do {
            for try await p in streamProvider(url, sha) {
                switch p {
                case .downloading(let f): phase = .downloading; progress = f; statusMessage = "Downloading \(Int(f * 100))%"
                case .verifying(let f): phase = .verifying; progress = f; statusMessage = "Verifying \(Int(f * 100))%"
                case .complete: phase = .complete; progress = 1.0; statusMessage = "Ready"
                }
            }
            if phase == .complete { onComplete(modelID) }
        } catch {
            phase = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
        }
    }
}
