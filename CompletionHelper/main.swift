import Foundation

// Inline-completion helper process. Loads a model via libllama and serves completions over a
// line-based JSON protocol on stdin/stdout — process isolation (a crash here never takes down
// Parrot) plus in-process KV-cache reuse for near-instant per-keystroke completion.
//
// Protocol:
//   stdin  : one JSON object per line  {"prefix": "...", "maxTokens": 12}
//   stdout : one JSON object per line  {"text": "..."}   (and {"ready":true} once warm)

struct Req: Decodable { let prefix: String; let maxTokens: Int? }
struct Resp: Encodable { let text: String }

let args = CommandLine.arguments
guard args.count > 1 else {
    FileHandle.standardError.write(Data("usage: ParrotCompletionHelper <model.gguf>\n".utf8))
    exit(2)
}

let session: LlamaSession
do {
    session = try LlamaSession(modelPath: args[1])
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

while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty, let data = line.data(using: .utf8),
          let req = try? JSONDecoder().decode(Req.self, from: data) else { continue }
    let text = session.complete(prefix: req.prefix, maxTokens: req.maxTokens ?? 12)
    emit(Resp(text: text))
}

// stdin closed → exit without running the model/Metal teardown (which can abort). The OS reclaims.
exit(0)
