import Foundation

actor LocalLLMService: @preconcurrency LLMServiceBase {
    static let shared = LocalLLMService()

    nonisolated var resolvedModel: String {
        let id = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.selectedModelID)
        return id?.replacingOccurrences(of: ".gguf", with: "") ?? "local-qwen"
    }

    nonisolated var extraServiceHeaders: [String: String] { [:] }

    func resolveURL() async throws -> URL {
        let port = try await ensureServerRunning()
        guard let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions") else {
            throw CorrectionError.serverNotRunning
        }
        return url
    }

    func resolveAPIKey() async throws -> String? { nil }

    func handleOpenAIHTTPStatus(_ statusCode: Int, data: Data) throws {
        switch statusCode {
        case 200:       return
        case 404:       throw CorrectionError.modelNotLoaded
        case 500, 502:  throw CorrectionError.serverTimeout
        case 503:       throw CorrectionError.serverNotRunning
        default:        throw CorrectionError.outputParsingFailed(raw: "HTTP \(statusCode)")
        }
    }

    private func ensureServerRunning() async throws -> Int {
        let port = await ServerManager.shared.currentPort
        if port > 0 { return port }
        guard let modelPath = ModelManager.shared.currentModelPath else {
            throw CorrectionError.serverNotRunning
        }
        let newPort = try await ServerManager.shared.ensureRunning(modelPath: modelPath)
        await ServerHealthMonitor.shared.startMonitoring()
        return newPort
    }
}
