# In-Process Completion Engine — Design Spec

**Date:** 2026-05-29
**Status:** Approved direction (user chose full in-process rework), pre-implementation
**Supersedes the inference part of:** `2026-05-29-inline-completion-sp1-design.md` (server `/completion` path)

## Why

The server-subprocess completion path hit a wall after many iterations: high per-keystroke latency
(HTTP + full prompt reprocessing), web-pretrained base models drifting into HTML/code, and no way to
run it well on 8 GB. Cotypist achieves instant, on-topic completion by running **libllama in-process**
with a warm KV cache and a curated model. This spec adopts that approach for Parrot.

## Goals
- **Instant**: first ghost token < ~80 ms after the typing pause on M-class hardware.
- **On-topic, clean**: no HTML/code drift; plain-text continuations in the user's language.
- **8 GB-capable**: one small model resident, tight KV cache, no second model/process for completion.
- **Granular**: a couple words per suggestion (already handled by `CompletionPostprocessor`).
- **Isolated/solid**: an inference crash must not take down Parrot.

## Non-goals
- Replacing the **correction** path (stays on `llama-server` — on-demand, isolation, instruct model).
- Cloud anything. All on-device.

## Architecture

### Process model: dedicated XPC helper running libllama
A separate **XPC service** (`ParrotCompletionService`) links libllama and owns the completion model.
- **Isolation**: helper crash ≠ app crash (keeps the "solid" requirement).
- **Speed**: XPC is fast local IPC (no HTTP, no JSON-over-TCP); the helper keeps the model + KV cache
  warm and streams tokens back.
- **8 GB**: one process, one small model, direct control over context size / KV.
- (Alternative considered: in-app libllama like Cotypist — slightly less RAM overhead but no crash
  isolation. Rejected for solidity. If XPC proves too heavy, revisit.)

### libllama bridge
- A SwiftPM C-interop target (`CLlama`) exposing `llama.h`. Link the already-bundled
  `libllama`/`ggml` dylibs (present in `Parrot.app/Contents/Frameworks`). Acquire matching `llama.h`
  headers (from the same llama.cpp build, e.g. Homebrew `/opt/homebrew/include`).
- Thin Swift wrapper `LlamaContext` (actor): load model, tokenize, decode, sample, detokenize,
  manage the KV cache, abort.

### KV cache reuse (the latency win)
- Keep the model + a persistent context warm in the helper.
- On each request, find the **longest common token prefix** with the previous request and only decode
  the new tokens (llama.cpp `llama_kv_cache_seq_rm` / prefix reuse). Typing one char ⇒ decode ~1 token.
- This is what makes it instant; impossible to do cleanly over the server HTTP path.

### Output quality controls (kill HTML/code drift at the source)
- **GBNF grammar / logit constraints**: constrain sampling to plain text (disallow `<`, `>`, `{`, `}`,
  backtick, and code-ish tokens) so the model physically cannot emit markup/code.
- Stop on newline / sentence boundary; `n_predict` small (whole-words, trimmed to maxWords in post).
- Anti-repetition penalties (already tuned: repeat/frequency/presence).
- Postprocessor (existing) stays as a safety net.

### Model
- A **curated small completion model** shipped/recommended via the catalog. Requirements: good plain-text
  continuation, small (≤~2 GB Q4 for 8 GB), low markup drift. Candidates to evaluate: a small **instruct**
  model used with a continuation prompt (less web-drift than a raw base) vs a clean base model. Pick by
  measured quality+latency+RAM, not assumption. (gemma-3-4b-pt works but drifts to HTML; evaluate
  alternatives like Qwen2.5-1.5B/3B, gemma-2-2b.)

## Integration (clean, minimal blast radius)
- `CompletionEngine` already depends on the `CompletionProviding` protocol. The new engine is
  `XPCCompletionProvider: CompletionProviding` — swap `CompletionEngine.shared`'s provider. Controller,
  overlay, `TabInterceptor`, `CompletionPostprocessor`, settings UI all stay unchanged.
- Feature-flag the provider: fall back to the current `LlamaCompletionClient` (server) if the helper is
  unavailable, so nothing regresses.

## Data flow
```
keystroke → debounce(~200ms) → caret context (AccessibilityBridge)
  → XPCCompletionProvider.complete(pre, maxWords)
      → XPC → helper: reuse KV prefix, decode new tokens, grammar-constrained sampling, stream
  → CompletionPostprocessor.clean (trim words, safety strip)
  → overlay ghost; Tab inserts (synthesized typing)
```

## Error handling / RAM
- Helper unavailable / crashes → provider returns nil → no suggestion (app unaffected); auto-relaunch helper.
- Context size small (e.g. 1024–2048) to bound KV RAM on 8 GB.
- Cancellation: new request aborts the in-flight decode in the helper.

## Testing
- `LlamaContext`: load tiny model, tokenize/detokenize round-trip, decode N tokens deterministically
  (seeded), KV prefix-reuse correctness, abort.
- Grammar constraint: output never contains `<>{}` / backticks (property test over many prefixes).
- `XPCCompletionProvider`: protocol conformance, timeout/crash → nil, supersede.
- Latency harness: keystroke→first token timing (smoke).
- Existing `CompletionPostprocessor` tests stay.

## Phased plan (each phase builds + verifies before the next)
1. **CLlama bridge**: SwiftPM C target + `llama.h`; `LlamaContext` loads a model and generates text in a
   unit test / CLI harness. Verify quality+latency vs the server path. **Gate: quality good, <80ms warm.**
2. **XPC helper**: move `LlamaContext` into `ParrotCompletionService`; app talks to it; warm + cancel.
3. **KV prefix reuse** across requests (the instant feel).
4. **Grammar/plain-text constraint** (kill HTML/code).
5. **`XPCCompletionProvider`** wired into `CompletionEngine` behind a flag; server path as fallback.
6. **Model curation** + catalog entry + 8 GB tuning.

## Risks
- C interop + matching `llama.h` to the bundled dylib version (ABI mismatch → crashes). Mitigate: build
  libllama from a pinned llama.cpp version and bundle both headers+dylib together.
- Metal from an XPC helper (works, but entitlements/sandbox config needed).
- Effort: multi-session. Phase 1 is the make-or-break feasibility gate.
