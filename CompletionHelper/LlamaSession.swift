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
        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = 999   // offload ALL layers to the Metal GPU (don't rely on the default)
        guard let m = llama_model_load_from_file(modelPath, mparams) else {
            throw NSError(domain: "LlamaSession", code: 1, userInfo: [NSLocalizedDescriptionKey: "model load failed"])
        }
        model = m
        vocab = llama_model_get_vocab(m)
        var cparams = llama_context_default_params()
        cparams.n_ctx = UInt32(contextSize)
        // With all layers on the GPU, generation is GPU-bound; a couple more CPU threads speed up
        // prompt prefill + sampling without stuttering the UI (the old n_threads=2 throttled us).
        cparams.n_threads = 4
        cparams.n_threads_batch = 6
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

    /// Highest-logit "real content" token (not end-of-generation, not pure whitespace). Used to force
    /// a continuation when the model would otherwise STOP before producing anything — small models
    /// often want to emit end-of-text/newline right after a clause ("…perché"), which gave empty
    /// suggestions ("spesso non compaiono"). Scans the logits once; only called on a first-token stop.
    private func bestContentToken() -> llama_token? {
        let logits = llama_get_logits_ith(ctx, -1) ?? llama_get_logits(ctx)
        guard let logits else { return nil }
        let n = Int32(llama_vocab_n_tokens(vocab))
        var bestID: llama_token = -1
        var bestLogit = -Float.greatestFiniteMagnitude
        for i in 0..<n {
            if logits[Int(i)] <= bestLogit { continue }
            if llama_vocab_is_eog(vocab, i) { continue }
            let p = piece(i)
            // Require an actual letter — skip whitespace/punctuation/digit-only tokens like "_", so a
            // forced continuation is a real word, never "_" (#5).
            if !p.contains(where: { $0.isLetter }) { continue }
            bestLogit = logits[Int(i)]; bestID = i
        }
        return bestID >= 0 ? bestID : nil
    }

    /// Vocab-token biases that strongly downweight CJK tokens. Built once on first use, cached.
    private lazy var cjkBias: [llama_logit_bias] = {
        var biases: [llama_logit_bias] = []
        let n = llama_vocab_n_tokens(vocab)
        for i in 0..<n {
            let p = piece(i)
            if p.unicodeScalars.contains(where: {
                (0x3400...0x9FFF).contains($0.value) ||
                (0x3040...0x30FF).contains($0.value) ||
                (0xAC00...0xD7AF).contains($0.value) ||
                (0xF900...0xFAFF).contains($0.value)
            }) {
                biases.append(llama_logit_bias(token: i, bias: -100.0))
            }
        }
        return biases
    }()

    /// Vocab-token biases that strongly downweight tokens carrying HTML/XML angle brackets. Web-
    /// pretrained base models (gemma-3-4b-pt) constantly drift into markup ("<strong>…</strong>"),
    /// which wastes the tiny budget and renders as corrupted/skipped suggestions. Suppressing the
    /// bracket tokens at the source stops the drift before it starts. Built once, cached.
    private lazy var markupBias: [llama_logit_bias] = {
        var biases: [llama_logit_bias] = []
        let n = llama_vocab_n_tokens(vocab)
        for i in 0..<n {
            let p = piece(i)
            if p.contains("<") || p.contains(">") {
                biases.append(llama_logit_bias(token: i, bias: -100.0))
            }
        }
        return biases
    }()

    /// Vocab-token biases for literal TAB / C0 control characters — a base model (gemma-3-4b-pt)
    /// emits them wedged between words ("\triesco \ta \trisolvere"), which are never wanted in prose
    /// → hard-suppress (-100). Newline is intentionally NOT biased (it is the natural completion stop,
    /// handled below). Applied only in prose mode (`suppressMarkup`); code editors want tabs verbatim.
    private lazy var noiseBias: [llama_logit_bias] = {
        var biases: [llama_logit_bias] = []
        let n = llama_vocab_n_tokens(vocab)
        for i in 0..<n {
            let p = piece(i)
            guard !p.isEmpty else { continue }
            if p.unicodeScalars.contains(where: { $0.value == 0x09 || ($0.value < 0x20 && $0.value != 0x0A) }) {
                biases.append(llama_logit_bias(token: i, bias: -100.0))
            }
        }
        return biases
    }()

    /// Generates a short continuation of `prefix`. Reuses KV for the shared prefix.
    /// `shouldCancel` is polled each token so a newer request can abandon this one mid-generation.
    func complete(prefix: String, maxTokens: Int, temperature: Float = 0.3, seed: UInt32 = 0,
                  latinOnly: Bool = false, repeatPenalty: Float = 1.0, suppressMarkup: Bool = true,
                  shouldCancel: () -> Bool = { false }) -> String {
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

        // Sampler chain: [logit_bias] → top_k → top_p → min_p → temp → repeat_penalty → dist.
        // CRITICAL ORDER: the logit biases must run BEFORE the truncation samplers (top_k/top_p/
        // min_p). When a markup/CJK token dominates the distribution, min_p prunes every alternative
        // out of the candidate set; a bias applied *after* that can only crush the lone survivor's
        // logit — it cannot resurrect the pruned alternatives, so the unwanted token still wins (this
        // is why `<strong>…</strong>` leaked through despite suppressMarkup). Biasing first drops the
        // markup/CJK tokens to -100 up front, so the truncation samplers keep the real alternatives.
        let smpl = llama_sampler_chain_init(llama_sampler_chain_default_params())
        if latinOnly && !cjkBias.isEmpty {
            cjkBias.withUnsafeBufferPointer { buf in
                llama_sampler_chain_add(smpl, llama_sampler_init_logit_bias(
                    llama_vocab_n_tokens(vocab), Int32(buf.count), buf.baseAddress))
            }
        }
        if suppressMarkup && !markupBias.isEmpty {
            markupBias.withUnsafeBufferPointer { buf in
                llama_sampler_chain_add(smpl, llama_sampler_init_logit_bias(
                    llama_vocab_n_tokens(vocab), Int32(buf.count), buf.baseAddress))
            }
        }
        if suppressMarkup && !noiseBias.isEmpty {
            noiseBias.withUnsafeBufferPointer { buf in
                llama_sampler_chain_add(smpl, llama_sampler_init_logit_bias(
                    llama_vocab_n_tokens(vocab), Int32(buf.count), buf.baseAddress))
            }
        }
        llama_sampler_chain_add(smpl, llama_sampler_init_top_k(20))
        llama_sampler_chain_add(smpl, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(smpl, llama_sampler_init_min_p(0.05, 1))
        llama_sampler_chain_add(smpl, llama_sampler_init_temp(temperature))
        llama_sampler_chain_add(smpl, llama_sampler_init_penalties(512, repeatPenalty, 0.0, 0.0))
        llama_sampler_chain_add(smpl, llama_sampler_init_dist(seed))
        defer { llama_sampler_free(smpl) }

        var generated: [llama_token] = []
        var out = ""
        var stoppedClean = false   // true if we stopped at a natural end (EOG / newline / cancel)
        for _ in 0..<maxTokens {
            if shouldCancel() { stoppedClean = true; break }   // newer request → abandon (discarded upstream)
            var id = llama_sampler_sample(smpl, ctx, -1)
            var pc = piece(id)
            // Does the model want to stop here? (end-of-generation, or a line break.)
            if llama_vocab_is_eog(vocab, id) || pc.contains("\n") {
                if out.isEmpty, let forced = bestContentToken() {
                    // It would stop BEFORE producing anything → force the best real word so a
                    // suggestion actually appears instead of nothing.
                    id = forced
                    pc = piece(id)
                } else {
                    stoppedClean = true; break   // natural end (after content) or no content available
                }
            }
            out += pc
            generated.append(id)
            batch = llama_batch_get_one(&id, 1)
            if llama_decode(ctx, batch) != 0 { break }
        }
        cached = promptTokens + generated
        // If we stopped only because we hit the token budget, the last token is usually a word
        // FRAGMENT ("...di fer" for "ferro") → looks corrupted. Trim back to the last word boundary,
        // but ONLY when there's a real (non-leading) space to trim to — otherwise a single
        // leading-spaced word (" parola") would be nuked to "" (the old bug behind empty suggestions).
        if !stoppedClean, let last = out.last, !last.isWhitespace,
           let lastSpace = out.lastIndex(of: " "),
           out[..<lastSpace].contains(where: { $0 != " " }) {
            out = String(out[..<lastSpace])
        }
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
