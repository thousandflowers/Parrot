import Foundation

// Inline-completion helper process. Loads a model via libllama and serves completions over a
// line-based JSON protocol on stdin/stdout — process isolation (a crash here never takes down
// Parrot) plus in-process KV-cache reuse for near-instant per-keystroke completion.
//
// Protocol:
//   stdin  : one JSON object per line  {"prefix": "...", "maxTokens": 12}
//   stdout : one JSON object per line  {"text": "..."}   (and {"ready":true} once warm)

struct Req: Decodable { let prefix: String; let maxTokens: Int?; let id: Int?; let latinOnly: Bool?; let seed: UInt32? }
struct Resp: Encodable { let text: String; let id: Int }   // echo the request id so the parent matches responses 1:1

let args = CommandLine.arguments
guard args.count > 1 else {
    FileHandle.standardError.write(Data("usage: ParrotCompletionHelper <model.gguf>\n".utf8))
    exit(2)
}

let session: LlamaSession
do {
    // RAM-aware context window, mirroring ServerManager.start: the prefix is capped to ~800 chars
    // upstream so 2048 suffices on low-RAM machines, while 16GB+ gets headroom for KV-cache reuse.
    let ramGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
    let ctx: Int32 = ramGB <= 8 ? 2048 : 4096
    session = try LlamaSession(modelPath: args[1], contextSize: ctx)
} catch {
    FileHandle.standardError.write(Data("helper: \(error.localizedDescription)\n".utf8))
    exit(1)
}

func emit(_ obj: Encodable) {
    guard let d = try? JSONEncoder().encode(AnyEncodable(obj)) else { return }
    FileHandle.standardOutput.write(d)
    FileHandle.standardOutput.write(Data("\n".utf8))
}
struct AnyEncodable: Encodable {
    let enc: (Encoder) throws -> Void
    init(_ e: Encodable) { enc = e.encode }
    func encode(to encoder: Encoder) throws { try enc(encoder) }
}

// Signal readiness so the parent knows the model is warm. Use FileHandle (unbuffered) for ALL
// output so lines never reorder relative to the responses below.
FileHandle.standardOutput.write(Data("{\"ready\":true}\n".utf8))

// Request lines are read on a background thread into a queue so the generation loop can notice a
// NEWER request arriving mid-completion and abandon the current one (cross-process supersede).
// We still emit exactly one response per request to keep the parent's request/response pairing.
final class RequestQueue: @unchecked Sendable {
    private let cond = NSCondition()
    private var lines: [(seq: Int, line: String)] = []
    private var nextSeq = 0
    private var stdinClosed = false

    func enqueue(_ line: String) {
        cond.lock(); defer { cond.unlock() }
        lines.append((nextSeq, line)); nextSeq += 1
        cond.signal()
    }
    func closeStdin() {
        cond.lock(); defer { cond.unlock() }
        stdinClosed = true; cond.signal()
    }
    /// Blocks until a request is available; returns nil once stdin is closed and the queue drains.
    func next() -> (seq: Int, line: String)? {
        cond.lock(); defer { cond.unlock() }
        while lines.isEmpty && !stdinClosed { cond.wait() }
        return lines.isEmpty ? nil : lines.removeFirst()
    }
    /// True if any queued request is newer than `seq` — the current generation should bail.
    func hasNewer(than seq: Int) -> Bool {
        cond.lock(); defer { cond.unlock() }
        return lines.contains { $0.seq > seq }
    }
}

let queue = RequestQueue()

let reader = Thread {
    while let line = readLine(strippingNewline: true) { queue.enqueue(line) }
    queue.closeStdin()
}
reader.stackSize = 1 << 20
reader.start()

while let (seq, line) = queue.next() {
    guard !line.isEmpty, let data = line.data(using: .utf8),
          let req = try? JSONDecoder().decode(Req.self, from: data) else { continue }
    let text = session.complete(prefix: req.prefix, maxTokens: req.maxTokens ?? 12,
                                seed: req.seed ?? 0,
                                latinOnly: req.latinOnly ?? false,
                                shouldCancel: { queue.hasNewer(than: seq) })
    emit(Resp(text: text, id: req.id ?? 0))
}

// stdin closed → terminate immediately. Use _exit (NOT exit): exit() runs atexit / C++ static
// destructors, and ggml-metal's device destructor aborts with `GGML_ASSERT([rsets->data count]==0)`
// during that teardown (llama.cpp PR 17869). _exit skips all of it; the OS reclaims the process.
_exit(0)
