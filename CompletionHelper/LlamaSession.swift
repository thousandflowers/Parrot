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
    private static let newlineByte: UInt8 = 0x0A

    init(modelPath: String, contextSize: Int32 = 2048) throws {
        // ggml >= 0.23 loads its compute backends (Metal, CPU, BLAS) as plugins. Search ONLY next to
        // this executable: the library also carries a compiled-in Homebrew path whose plugins exist
        // on dev machines but carry a foreign signature the hardened runtime rejects, and the loader
        // stops at the first existing candidate instead of falling through to the next directory.
        if let exeDir = Bundle.main.executableURL?.deletingLastPathComponent().path {
            ggml_backend_load_all_from_path(exeDir)
        }
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

    /// Raw UTF-8 bytes of a token. May be an incomplete character (multi-byte chars span tokens).
    private func pieceBytes(_ tok: llama_token) -> [UInt8] {
        var buf = [CChar](repeating: 0, count: 128)
        let m = llama_token_to_piece(vocab, tok, &buf, 128, 0, false)
        guard m > 0 else { return [] }
        return buf.prefix(Int(m)).map { UInt8(bitPattern: $0) }
    }

    /// A single token decoded on its own — fine for vocab classification, NOT for building output.
    private func piece(_ tok: llama_token) -> String {
        String(decoding: pieceBytes(tok), as: UTF8.self)
    }

    /// Drops KV entries at positions >= `keep` and records the first `keep` of `tokens` as resident.
    /// If the backend cannot remove a partial range, clears the whole memory instead, so `cached`
    /// never claims tokens that are no longer in the KV cache.
    private func truncateResident(to keep: Int, of tokens: [llama_token]) {
        let mem = llama_get_memory(ctx)
        if llama_memory_seq_rm(mem, 0, Int32(keep), -1) {
            cached = Array(tokens.prefix(keep))
        } else {
            llama_memory_clear(mem, true)
            cached = []
        }
    }

    /// A failed decode may leave partially processed ubatches in memory (see llama.h): the resident
    /// state is unknown, so drop it entirely and let the next call rebuild from scratch.
    /// Decodes `tokens` into sequence 0 at explicit positions `startPos...`, requesting logits for
    /// the last one (what the sampler reads). llama_batch_ext + llama_process replace the
    /// deprecated llama_batch_get_one + llama_decode (llama.cpp 1.x).
    private func decode(_ tokens: [llama_token], startPos: Int) -> Bool {
        guard !tokens.isEmpty, let batch = llama_batch_ext_init(ctx) else { return false }
        defer { llama_batch_ext_free(batch) }
        for (offset, token) in tokens.enumerated() {
            let idx = llama_batch_ext_add_token(batch, 0, token)
            guard idx >= 0 else { return false }
            var pos = llama_pos(startPos + offset)
            guard llama_batch_ext_set_pos(batch, idx, &pos) else { return false }
            if offset == tokens.count - 1 {
                guard llama_batch_ext_set_output_logits(batch, idx, true) else { return false }
            }
        }
        return llama_process(ctx, LLAMA_PROCESS_TYPE_DECODE, batch) == 0
    }

    private func resetResident() {
        llama_memory_clear(llama_get_memory(ctx), true)
        cached = []
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

        // Drop KV beyond the shared prefix; `cached` now reflects exactly what is resident.
        truncateResident(to: p, of: promptTokens)
        p = cached.count                              // 0 if the backend had to clear everything

        // Decode the new prompt tokens (auto position resumes at p).
        guard decode(Array(promptTokens[p...]), startPos: p) else { resetResident(); return "" }
        cached = promptTokens

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
        // llama.cpp >= 0.4.0 (Homebrew) re-added n_vocab as the first parameter.
        llama_sampler_chain_add(smpl, llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), 512, repeatPenalty, 0.0, 0.0))
        llama_sampler_chain_add(smpl, llama_sampler_init_dist(seed))
        defer { llama_sampler_free(smpl) }

        var outBytes: [UInt8] = []   // accumulated raw bytes; decoded once (multi-token UTF-8 chars)
        var stoppedClean = false   // true if we stopped at a natural end (EOG / newline / cancel)
        for _ in 0..<maxTokens {
            if shouldCancel() { stoppedClean = true; break }   // newer request → abandon (discarded upstream)
            var id = llama_sampler_sample(smpl, ctx, -1)
            var pc = pieceBytes(id)
            // Does the model want to stop here? (end-of-generation, or a line break.)
            if llama_vocab_is_eog(vocab, id) || pc.contains(Self.newlineByte) {
                if outBytes.isEmpty, let forced = bestContentToken() {
                    // It would stop BEFORE producing anything → force the best real word so a
                    // suggestion actually appears instead of nothing.
                    id = forced
                    pc = pieceBytes(id)
                } else {
                    stoppedClean = true; break   // natural end (after content) or no content available
                }
            }
            outBytes += pc
            // Only a successfully decoded token is resident in the KV cache.
            guard decode([id], startPos: cached.count) else { resetResident(); break }
            cached.append(id)
        }
        // Decode once; a budget stop mid-character drops the incomplete tail instead of U+FFFD.
        var out = UTF8Text.decodeDroppingIncompleteTail(outBytes)
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
