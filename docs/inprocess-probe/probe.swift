import CLlama
import Foundation

// Phase-1 feasibility probe: load a model via libllama in-process and generate text.
let modelPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
    : NSString(string: "~/Library/Application Support/Parrot/Models/qwen2.5-1.5b-instruct-q4_k_m.gguf").expandingTildeInPath
let prompt = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Caro Marco, ti scrivo per"

llama_backend_init()
var mparams = llama_model_default_params()
guard let model = llama_model_load_from_file(modelPath, mparams) else {
    fputs("FAIL: model load\n", stderr); exit(1)
}
let vocab = llama_model_get_vocab(model)
var cparams = llama_context_default_params()
cparams.n_ctx = 512
guard let ctx = llama_init_from_model(model, cparams) else { fputs("FAIL: ctx\n", stderr); exit(1) }

// tokenize
var tokens = [llama_token](repeating: 0, count: 256)
let n = prompt.withCString { cstr in
    llama_tokenize(vocab, cstr, Int32(strlen(cstr)), &tokens, 256, true, false)
}
guard n > 0 else { fputs("FAIL: tokenize \(n)\n", stderr); exit(1) }
tokens = Array(tokens.prefix(Int(n)))

// greedy sampler chain
let smpl = llama_sampler_chain_init(llama_sampler_chain_default_params())
llama_sampler_chain_add(smpl, llama_sampler_init_greedy())

func piece(_ tok: llama_token) -> String {
    var buf = [CChar](repeating: 0, count: 128)
    let m = llama_token_to_piece(vocab, tok, &buf, 128, 0, false)
    guard m > 0 else { return "" }
    return String(decoding: buf.prefix(Int(m)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

let start = Date()
var batch = llama_batch_get_one(&tokens, Int32(tokens.count))
var out = ""
for _ in 0..<16 {
    guard llama_decode(ctx, batch) == 0 else { fputs("FAIL: decode\n", stderr); break }
    var id = llama_sampler_sample(smpl, ctx, -1)
    if llama_vocab_is_eog(vocab, id) { break }
    let p = piece(id)
    if p.contains("\n") { out += p.replacingOccurrences(of: "\n", with: " "); break }
    out += p
    batch = llama_batch_get_one(&id, 1)
}
let ms = Date().timeIntervalSince(start) * 1000
print("PROMPT: \(prompt)")
print("OUTPUT:\(out)")
print(String(format: "GEN latency (16 tok incl prompt): %.0f ms", ms))
llama_free(ctx); llama_model_free(model); llama_backend_free()
