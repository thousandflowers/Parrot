# In-Process libllama Probe (Phase 1 feasibility — PASSED 2026-05-29)

Proves the Swift↔libllama binding for the in-process completion engine
(see `../specs/2026-05-29-inprocess-completion-design.md`).

## Build & run
```
swiftc probe.swift -I . -L/opt/homebrew/lib -lllama \
  -Xlinker -rpath -Xlinker /opt/homebrew/lib -o probe
./probe "<model.gguf>" "Caro Marco, ti scrivo per"   2>/dev/null
```

## Result (llama.cpp 9370, M2 Pro)
- qwen2.5-1.5b → "informarti che il tuo amico Marco ha avuto un incidente. Mi"
- gemma-3-4b-pt (base) → "ringraziarti per la tua disponibilità e per la tua professionalità." (clean, no HTML)
- ~410 ms for 16 tokens COLD (full prompt). KV-prefix reuse will make per-keystroke generation near-instant.

## Next (Phase 2+)
Move `LlamaContext` into an XPC helper, add KV prefix reuse, grammar-constrained plain-text
sampling, then wire as `XPCCompletionProvider: CompletionProviding`.
