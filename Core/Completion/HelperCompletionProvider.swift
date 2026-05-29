import Foundation
import OSLog

/// Completion provider backed by the in-process `ParrotCompletionHelper` subprocess (libllama with
/// warm KV-cache reuse). Used when a dedicated completion model is configured and fits RAM; otherwise
/// delegates to the server-based `LlamaCompletionClient`. The helper is isolated (a crash there never
/// takes down Parrot) and every call is bounded by a timeout so it can never hang typing.
actor HelperCompletionProvider: CompletionProviding {
    private let fallback = LlamaCompletionClient()

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var modelInUse: String?
    private var buffer = Data()
    private var pending: CheckedContinuation<String, Never>?

    private struct Req: Encodable { let prefix: String; let maxTokens: Int }
    private struct Resp: Decodable { let text: String }

    func complete(context: CompletionContext, maxWords: Int) async throws -> String {
        guard let modelPath = await dedicatedModelPath(), ramAllows(modelPath) else {
            return try await fallback.complete(context: context, maxWords: maxWords)
        }
        do {
            try ensureHelper(modelPath: modelPath)
        } catch {
            Logger.infra.debug("completion helper launch failed (\(error.localizedDescription, privacy: .public)) — server fallback")
            return try await fallback.complete(context: context, maxWords: maxWords)
        }

        let pre = String(context.preContext.suffix(Constants.completionMaxPrefixChars))
        guard let line = try? JSONEncoder().encode(Req(prefix: pre, maxTokens: max(4, maxWords * 3))),
              let stdin = stdinHandle else {
            return try await fallback.complete(context: context, maxWords: maxWords)
        }

        // One request in flight at a time; supersede handled upstream by CompletionEngine.
        let text: String? = await withTaskGroup(of: String?.self) { group in
            group.addTask { await self.sendAndAwait(line, stdin: stdin) }
            group.addTask { try? await Task.sleep(for: .seconds(4)); return nil }   // timeout guard
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let text else {
            // Timeout/EOF → drop the helper so the next call relaunches it cleanly.
            teardownHelper()
            return ""
        }
        return text
    }

    // MARK: - Pipe request/response
    private func sendAndAwait(_ jsonLine: Data, stdin: FileHandle) async -> String {
        await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            pending = cont
            var data = jsonLine
            data.append(0x0A)   // newline
            do { try stdin.write(contentsOf: data) }
            catch { resumePending(with: "") }
        }
    }

    private func onData(_ chunk: Data) {
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let resp = try? JSONDecoder().decode(Resp.self, from: lineData) else { continue }  // skip {"ready":true}
            resumePending(with: resp.text)
        }
    }

    private func resumePending(with text: String) {
        guard let cont = pending else { return }
        pending = nil
        cont.resume(returning: text)
    }

    // MARK: - Process lifecycle
    private func ensureHelper(modelPath: String) throws {
        if let p = process, p.isRunning, modelInUse == modelPath { return }
        teardownHelper()

        guard let helperURL = Self.helperExecutableURL() else {
            throw NSError(domain: "Helper", code: 1, userInfo: [NSLocalizedDescriptionKey: "helper binary not found"])
        }
        let proc = Process()
        proc.executableURL = helperURL
        proc.arguments = [modelPath]
        // Low priority so per-keystroke inference yields to the UI and never stutters the machine.
        proc.qualityOfService = .utility
        let inPipe = Pipe(), outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty, let self else { return }
            Task { await self.onData(d) }
        }
        try proc.run()
        process = proc
        stdinHandle = inPipe.fileHandleForWriting
        modelInUse = modelPath
        Logger.infra.info("completion helper started for \(modelPath, privacy: .public)")
    }

    private func teardownHelper() {
        resumePending(with: "")
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        stdinHandle = nil
        modelInUse = nil
        buffer.removeAll()
    }

    private static func helperExecutableURL() -> URL? {
        // Bundled next to the main executable in the .app, or in the SwiftPM build dir for dev.
        let exeDir = Bundle.main.executableURL?.deletingLastPathComponent()
        if let u = exeDir?.appendingPathComponent("ParrotCompletionHelper"), FileManager.default.isExecutableFile(atPath: u.path) {
            return u
        }
        return nil
    }

    // MARK: - Model selection / RAM
    private func dedicatedModelPath() async -> String? {
        let compID = (UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.completionModelID) ?? "")
            .trimmingCharacters(in: .whitespaces)
        guard !compID.isEmpty else { return nil }   // no dedicated model → use server fallback
        return await ModelManager.shared.localModels()
            .first(where: { $0.id.caseInsensitiveCompare(compID) == .orderedSame })?.path
    }

    private func ramAllows(_ modelPath: String) -> Bool {
        let ram = Double(ProcessInfo.processInfo.physicalMemory)
        let size = Double((try? FileManager.default.attributesOfItem(atPath: modelPath))?[.size] as? Int64 ?? 0)
        // The helper holds one model; keep it under ~35% of RAM (correction model + OS need the rest).
        return size > 0 && size < ram * 0.35
    }
}
