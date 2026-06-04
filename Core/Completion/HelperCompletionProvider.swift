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
    private var pendingID = -1          // id of the request `pending` is waiting for
    private var nextRequestID = 0       // monotonic request id; lets us match responses 1:1
    /// The helper signals `{"ready":true}` once the model + Metal backend are warm. Cold start is
    /// slow (Metal library compile ~8s on first launch), so the first request must tolerate that;
    /// after ready, inference is fast and a short timeout protects typing latency.
    private var helperReady = false

    // Serialises pipe exchanges. The debounce + fast typing can start several overlapping
    // `complete()` calls; without serialisation their request/response lines interleave on the
    // single pipe and desync (the final request's response gets dropped → nil suggestions after the
    // first). Each call takes this mutex around its send/await so exchanges are strictly 1:1.
    private var pipeBusy = false
    private var pipeWaiters: [CheckedContinuation<Void, Never>] = []
    private func acquirePipe() async {
        if !pipeBusy { pipeBusy = true; return }
        await withCheckedContinuation { pipeWaiters.append($0) }
    }
    private func releasePipe() {
        if pipeWaiters.isEmpty { pipeBusy = false } else { pipeWaiters.removeFirst().resume() }
    }

    private struct Req: Encodable { let prefix: String; let maxTokens: Int; let id: Int; let latinOnly: Bool; let seed: UInt32 }
    private struct Resp: Decodable { let text: String; let id: Int }

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

        // Raw continuation of the user's text. This is the RIGHT approach for inline completion: a
        // BASE model (gemma-3-4b-pt) continues arbitrary text reliably. Instruct models were tried
        // and REFUSE to continue open-ended text (they reply or emit nothing), so they are unusable
        // here. The postprocessor strips the base model's occasional web/HTML/escaping drift.
        let pre = String(context.preContext.suffix(Constants.completionMaxPrefixChars))
        let reqID = { nextRequestID += 1; return nextRequestID }()
        // latinOnly: true when the context contains no CJK characters — signals the helper to apply
        // a logit-bias that strongly downweights CJK tokens, preventing wrong-script output.
        let latinOnly = !pre.unicodeScalars.contains {
            (0x4E00...0x9FFF).contains($0.value) ||
            (0x3040...0x30FF).contains($0.value) ||
            (0xAC00...0xD7AF).contains($0.value)
        }
        // +4 token slack over the word budget: the helper trims a trailing word FRAGMENT on a
        // budget-stop, so a little extra room keeps the trimmed result at the intended word count.
        guard let line = try? JSONEncoder().encode(Req(prefix: pre, maxTokens: max(12, maxWords * 3 + 4), id: reqID, latinOnly: latinOnly, seed: context.generationSeed)),
              let stdin = stdinHandle else {
            return try await fallback.complete(context: context, maxWords: maxWords)
        }

        // Serialise the pipe exchange so overlapping requests never interleave on the single pipe.
        let tBeforePipe = Date()
        await acquirePipe()
        let tInfer = Date()                 // DIAG: time blocked on the pipe vs time in inference
        defer { releasePipe() }

        // Warm timeout 12s: gemma-3-4b's FIRST inference compiles Metal kernels (slow, one-time); warm
        // calls are much faster. Cold (pre-ready) start loads the model → 60s. On timeout we do NOT
        // tear down the helper — that caused a cold-restart flicker spiral. Request ids let a late
        // response for an abandoned request be ignored, so the helper stays warm and the next works.
        let timeoutSeconds: Double = helperReady ? 12 : 60
        let text: String? = await withTaskGroup(of: String?.self) { group in
            group.addTask { await self.sendAndAwait(line, id: reqID, stdin: stdin) }
            group.addTask { try? await Task.sleep(for: .seconds(timeoutSeconds)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        CrashLogger.log("DIAG helper-timing: id=\(reqID) pipeWait=\(Int(tInfer.timeIntervalSince(tBeforePipe)*1000))ms infer=\(Int(Date().timeIntervalSince(tInfer)*1000))ms ready=\(helperReady) result=\(text == nil ? "nil" : "len=\(text!.count)")")
        guard let text else {
            // Timed out: abandon THIS request but keep the helper ALIVE (no teardown → no spiral).
            // Clear the dangling continuation; a late response for reqID is ignored by id-match below.
            resumePending(with: "")
            return ""
        }
        return text
    }

    // MARK: - Pipe request/response
    private func sendAndAwait(_ jsonLine: Data, id: Int, stdin: FileHandle) async -> String {
        await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            // Never overwrite an in-flight continuation without resuming it — that would leak it
            // (runtime warning + corrupted actor state). Resume any stale one with an empty result.
            if let stale = pending {
                #if DEBUG
                CrashLogger.log("DIAG helper: STALE cleanup → prev request resumed with ''")
                #endif
                pending = nil; stale.resume(returning: "")
            }
            pending = cont
            pendingID = id
            var data = jsonLine
            data.append(0x0A)   // newline
            do { try stdin.write(contentsOf: data) }
            catch {
                #if DEBUG
                CrashLogger.log("DIAG helper: WRITE FAILED \(error.localizedDescription)")
                #endif
                resumePending(with: "")
            }
        }
    }

    private func onData(_ chunk: Data) {
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            // The readiness line means the model finished loading; mark warm so later requests use
            // the short timeout. It is not a completion response.
            if let s = String(data: lineData, encoding: .utf8), s.contains("\"ready\"") {
                helperReady = true
                continue
            }
            guard let resp = try? JSONDecoder().decode(Resp.self, from: lineData) else {
                #if DEBUG
                CrashLogger.log("DIAG helper: onData UNDECODABLE line len=\(lineData.count)")
                #endif
                continue
            }
            #if DEBUG
            CrashLogger.log("DIAG helper: onData resp id=\(resp.id) len=\(resp.text.count) want=\(pendingID)")
            #endif
            helperReady = true   // a real response also proves the helper is warm
            // Resolve ONLY if this is the response for the request we're waiting on. A late response
            // for an abandoned (timed-out/superseded) request carries a stale id → ignore it.
            if resp.id == pendingID { resumePending(with: resp.text) }
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
        #if DEBUG
        CrashLogger.log("DIAG helper: (re)launch — had process=\(process != nil) running=\(process?.isRunning ?? false) modelChanged=\(modelInUse != nil && modelInUse != modelPath)")
        #endif
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
        helperReady = false
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
        guard !compID.isEmpty else { return bundledModelPath() }   // default to the bundled model (Wren standalone)
        // A user-chosen model wins — but ONLY if its file actually resolves on disk. A stale config
        // pointing at a removed model or a broken symlink (e.g. an `.i1` link to another app's model
        // that was deleted) must NOT silently match and then fail; fall through to the bundled model.
        let fm = FileManager.default
        if let p = await ModelManager.shared.localModels()
            .first(where: { $0.id.caseInsensitiveCompare(compID) == .orderedSame })?.path,
           fm.fileExists(atPath: p) {   // follows symlinks → false for a broken link
            return p
        }
        return bundledModelPath()
    }

    /// A `.gguf` shipped inside the app bundle (`Contents/Resources/Models/`). This is how the
    /// standalone Wren runs out of the box with no model download. Returns nil when none is bundled
    /// (e.g. Parrot), so that path falls through to the server fallback.
    private func bundledModelPath() -> String? {
        guard let resURL = Bundle.main.resourceURL else { return nil }
        let modelsDir = resURL.appendingPathComponent("Models")
        let ggufs = (try? FileManager.default.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "gguf" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        return ggufs.first?.path
    }

    private func ramAllows(_ modelPath: String) -> Bool {
        let ram = Double(ProcessInfo.processInfo.physicalMemory)
        let size = Double((try? FileManager.default.attributesOfItem(atPath: modelPath))?[.size] as? Int64 ?? 0)
        // The helper holds one model; keep it under ~35% of RAM (correction model + OS need the rest).
        return size > 0 && size < ram * 0.35
    }
}
