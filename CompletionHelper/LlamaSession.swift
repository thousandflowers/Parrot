import CLlama
import Foundation

/// In-process llama.cpp session for inline completion. Keeps the model + context warm and reuses
/// the KV cache across calls (only the new tokens past the common prefix are decoded), which is
/// what makes per-keystroke completion near-instant.
final class LlamaSession {
    private let model: OpaquePointer
    private let vocab: OpaquePointer
    private var ctx: OpaquePointer
    private let nCtx: Int32
    private var cached: [llama_token] = []   // tokens currently resident in the KV cache (seq 0)

    init(modelPath: String, contextSize: Int32 = 2048) throws {
        llama_backend_init()
        let mparams = llama_model_default_params()
        guard let m = llama_model_load_from_file(modelPath, mparams) else {
            throw NSError(domain: "LlamaSession", code: 1, userInfo: [NSLocalizedDescriptionKey: "model load failed"])
        }
        model = m
        vocab = llama_model_get_vocab(m)
        var cparams = llama_context_default_params()
        cparams.n_ctx = UInt32(contextSize)
        // Few threads on purpose: completion runs on every typing pause, so it must NOT saturate the
        // CPU or the whole machine stutters. Low thread counts keep cores free for the UI.
        cparams.n_threads = 2
        cparams.n_threads_batch = 4
        guard let c = llama_init_from_model(m, cparams) else {
            llama_model_free(m)
            throw NSError(domain: "LlamaSession", code: 2, userInfo: [NSLocalizedDescriptionKey: "context init failed"])
        }
        ctx = c
        nCtx = contextSize
    }

    private func tokenize(_ text: String) -> [llama_token] {
        var buf = [llama_token](repeating: 0, count: text.utf8.count + 8)
        let n = text.withCString { cstr in
            llama_tokenize(vocab, cstr, Int32(strlen(cstr)), &buf, Int32(buf.count), true, false)
        }
        guard n > 0 else { return [] }
        return Array(buf.prefix(Int(n)))
    }

    private func piece(_ tok: llama_token) -> String {
        var buf = [CChar](repeating: 0, count: 128)
        let m = llama_token_to_piece(vocab, tok, &buf, 128, 0, false)
        guard m > 0 else { return "" }
        return String(decoding: buf.prefix(Int(m)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Generates a short continuation of `prefix`. Reuses KV for the shared prefix.
    func complete(prefix: String, maxTokens: Int, temperature: Float = 0.3, seed: UInt32 = 0) -> String {
        var promptTokens = tokenize(prefix)
        guard !promptTokens.isEmpty else { return "" }
        // Keep within context: drop oldest prompt tokens if needed, leaving room for generation.
        let maxPrompt = Int(nCtx) - maxTokens - 8
        if promptTokens.count > maxPrompt, maxPrompt > 0 {
            promptTokens = Array(promptTokens.suffix(maxPrompt))
            cached = []   // truncation breaks prefix alignment → rebuild
        }

        // Common prefix with what's already in the KV cache.
        var p = 0
        let limit = min(cached.count, promptTokens.count)
        while p < limit && cached[p] == promptTokens[p] { p += 1 }
        // Never reuse the entire prompt (need at least the last token to produce logits).
        if p == promptTokens.count { p = promptTokens.count - 1 }

        let mem = llama_get_memory(ctx)
        llama_memory_seq_rm(mem, 0, Int32(p), -1)   // drop KV beyond the shared prefix

        // Decode the new prompt tokens (auto position resumes at p).
        var newTokens = Array(promptTokens[p...])
        var batch = llama_batch_get_one(&newTokens, Int32(newTokens.count))
        guard llama_decode(ctx, batch) == 0 else { return "" }

        // Sampler chain: top_k → top_p → temp → dist (light randomness avoids greedy loops).
        let smpl = llama_sampler_chain_init(llama_sampler_chain_default_params())
        llama_sampler_chain_add(smpl, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(smpl, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(smpl, llama_sampler_init_temp(temperature))
        llama_sampler_chain_add(smpl, llama_sampler_init_dist(seed))
        defer { llama_sampler_free(smpl) }

        var generated: [llama_token] = []
        var out = ""
        for _ in 0..<maxTokens {
            var id = llama_sampler_sample(smpl, ctx, -1)
            if llama_vocab_is_eog(vocab, id) { break }
            let pc = piece(id)
            if pc.contains("\n") { break }   // short completion: stop at line break
            out += pc
            generated.append(id)
            batch = llama_batch_get_one(&id, 1)
            if llama_decode(ctx, batch) != 0 { break }
        }
        cached = promptTokens + generated
        return out
    }

    deinit {
        // Note: skip llama_backend_free() — the global GGML/Metal backend teardown can abort at
        // process exit. The OS reclaims everything when the helper exits, so freeing the context
        // and model is enough for a clean in-process lifecycle.
        llama_free(ctx)
        llama_model_free(model)
    }
}
