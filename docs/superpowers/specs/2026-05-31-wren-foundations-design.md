# Wren Foundations (Phase 0) — Design

**Date:** 2026-05-31
**Status:** Approved
**Scope:** Phase 0 of the program "make Wren better than KeyType and similar apps in every aspect."

## Program context

Wren is on-device inline completion for macOS (ghost text, accept with Tab), sharing the
`core` codebase with Parrot. Goal: surpass KeyType (and Cotypist et al.) on all eight
dimensions — completion quality, latency, context awareness, personalization, app
compatibility, UX polish, privacy, distribution. The program is built in ordered phases,
each with its own spec → plan → implementation. This document covers **Phase 0: Foundations
(app compatibility + latency)** — the plumbing every later phase builds on.

Later phases (out of scope here): F1 constrained generation (logit masking + trie), F2 screen
context, F3 personalization (style/contacts), F4 UX polish, F5 onboarding/distribution.

## Goal (Phase 0 success criteria)

1. **Works in every app** — ghost text / completion available in every text field: native,
   Electron/Chromium, web, terminal. No app where it silently does nothing.
2. **Latency budget (p95):** <50ms for learned/cache hits, <300ms for model inference, measured
   from "user stops typing" to "ghost visible."
3. **Zero clipboard hack** — no hidden copy/paste, no hardcoded bundle-ID lists. Read/insert via
   AX or a clean universal fallback; capability decisions made on observed facts, never app names.
4. **Robustness** — never crash, never corrupt/duplicate text, never leave a ghost suggestion,
   recover from AX timeouts.

## Architecture

**Principle for the "every app" guarantee: tiered fallback with no gap.** Every operation
(read context, find caret, insert) has a chain of backends from best to universal. The last
link always works.

### `TextSurface` protocol — single interface, three operations

```swift
protocol TextSurface {
    func readContext() -> (pre: String, post: String)?   // text around the caret
    func caretRect() -> CGRect?                            // where to draw the ghost
    func insert(_ text: String)                           // accept a completion
    func replaceLastWord(wrong: String, with: String)     // typo fix
}
```

### Three backends, chosen at runtime by capability (no bundle list)

| Backend | Selected when | How |
|---|---|---|
| `NativeAXSurface` | AX exposes `kAXValue` + selected range | direct AX read/write. Native Cocoa apps. |
| `ChromiumAXSurface` | Chromium/Electron process, AX initially blind | set `AXManualAccessibility=true` on the pid to force real AX, then behaves like NativeAX. |
| `UniversalSurface` | AX blind (no value/caret even after the flag) | typed-input buffer + keystroke insert. No clipboard. |

### `UniversalSurface` — the "every app" guarantee without clipboard

- **Read context** → **typed-input buffer**: the existing CGEventTap (already live for Tab)
  observes the keys *the user types* and reconstructs the field's recent text locally. No AX,
  no clipboard, works in any focused field. Buffer is per-focus, reset on focus change.
- **Insert** → keystroke synthesis (already implemented). Works universally in any editable field.
- **Caret rect** → tiered: AX caret → IMK marked-text rect → estimate from cursor position.
  *The one honest degradation:* if an app exposes no caret in any way, the ghost falls back to a
  small floating hint near the mouse cursor instead of inline. Context + accept still work fully.

### Capability probe

`SurfaceProbe`: on focus, try AX read → if empty and the process is Chromium, apply the flag and
retry → if still empty, use `UniversalSurface`. Decision is made on *observed facts*, never on the
bundle ID. The chosen surface is cached per-focus (see Latency §3).

## Latency pipeline

Budget: <50ms learned/cache, <300ms model. Measured from "stop typing" to "ghost visible."

```
keystroke → debounce → probe surface → readContext →
  ├─ cache/learned hit? → postprocess → render ghost          [target <50ms]
  └─ miss → model infer (streaming) → postprocess → render    [target <300ms]
```

Interventions:

1. **Adaptive debounce** — currently fixed min 120ms. New: starts low (~40ms), lengthens only
   while the user types fast. A pause shows the ghost almost immediately.
2. **Learned/cache path bypasses the model** — already exists; promoted to the first gate and
   instrumented to guarantee <50ms. In-memory LRU cache on `(contextHash → suggestion)`, in
   addition to the on-disk learning store.
3. **Probe + readContext cached per-focus** — do not re-probe capabilities on every keystroke.
   Probe once per field, reuse until focus changes. Removes AX work from the hot path.
4. **Streaming inference with early-render** — do not wait for the whole completion. As soon as
   the model produces the first 1–2 valid words, render the ghost; the rest extends as it
   generates. The user sees something within budget even on long completions.
5. **Aggressive cancellation** — every new keystroke cancels in-flight inference (`suggestionGen`
   + `cancelPending` exist). Made certain: a cancellation token is threaded down to the llama.cpp
   `n_predict` loop, which checks it.
6. **Always-on instrumentation** — `LatencyTracer` records ms per stage. Debug logs; release keeps
   p50/p95 percentiles for the diagnostics panel. Makes criterion #2 verifiable.

**Cold path** (first completion after idle): the model may be evicted from RAM. Mitigated with
keep-warm — a light periodic ping to `CompletionHelper` while Wren is active keeps the weights
mmap-resident.

## Robustness

1. **Stale request — one ghost, always the right one.** Every suggestion carries its `gen`;
   render and accept check `gen == current` before touching the screen or the field. Late
   inference from an old generation is discarded, never shown.
2. **Atomic insertion — no duplication/corruption.** Accept freezes state (text+pid+kind captured
   before the await). After insert, verify by re-reading the field; if the inserted text is absent
   (AX setValue silently failed), fall back to keystroke once — never loop. `replaceLastWord`
   exact-matches the wrong word before deleting; if it does not match (user already edited), abort
   instead of deleting blindly.
3. **AX timeout — never block the main actor.** Each `AXUIElementCopyAttributeValue` runs behind a
   timeout (~50ms). On expiry, treat as "AX blind" → fall back to `UniversalSurface`. An
   unresponsive app never freezes Wren.
4. **Ghost cleanup on every transition.** The ghost hides on: focus change, app change, click,
   scroll, Esc, any non-Tab key. The overlay is a separate `CompletionOverlayWindow` and never
   interferes with the real field.
5. **Crash isolation.** llama.cpp already runs out-of-process (`CompletionHelper`). If the helper
   crashes/hangs, Wren detects it (timeout/XPC error), restarts it, and serves cache/learned in the
   meantime. The main app stays alive.
6. **Typed-input buffer coherence.** The keylog buffer can diverge from the real field (paste,
   arrow keys, undo). Invalidate on navigation/edit keys (arrows, cmd-V, cmd-Z, click) → reset the
   buffer and rebuild from new typing. Better no suggestion than one on wrong context.

## Components

New components, each testable in isolation:

| Component | Responsibility | Depends on |
|---|---|---|
| `TextSurface` (protocol) | single read/caret/insert interface | — |
| `NativeAXSurface` | AX Cocoa backend | AccessibilityBridge |
| `ChromiumAXSurface` | `AXManualAccessibility` flag + AX | AccessibilityBridge |
| `UniversalSurface` | typed-buffer + keystroke insert | TypedInputBuffer, TabInterceptor |
| `SurfaceProbe` | choose backend at runtime by capability | the three surfaces |
| `TypedInputBuffer` | rebuild context from typed keys | CGEventTap |
| `LatencyTracer` | measure ms per stage, p50/p95 | — |
| `SuggestionCache` | in-memory LRU contextHash→suggestion | — |

**Targeted refactor (not gratuitous):** `AccessibilityBridge.swift` (~30KB, monolithic). Extract
read/insert logic behind `TextSurface`; the bridge stays a low-level AX wrapper.
`CompletionController.requestSuggestion()` moves from direct AX calls to
`surface = SurfaceProbe.current()`. No unrelated refactoring.

## Testing

Each unit in isolation:

- `TypedInputBuffer`: synthetic key input → expected context. Reset on navigation. Pure, no AX.
- `SuggestionCache`: hit/miss/LRU eviction. Pure.
- `SurfaceProbe`: fake surfaces with varying capabilities → verify the right backend is chosen.
  No real app.
- `LatencyTracer`: correct percentiles over known samples.
- `TextSurface` (per backend): mock AX element → read/insert/caret. `replaceLastWord` with a
  non-matching word → aborts.
- **Manual integration** (real-app checklist): TextEdit (native), Slack/VSCode (Chromium),
  Terminal / an AX-blind app (universal), Safari (web). App × operation matrix, criterion "every app."

## Acceptance metrics (verifiable)

1. Context readable in every app in the matrix (AX or buffer).
2. p95 latency: <50ms learned, <300ms model (from `LatencyTracer`).
3. Zero clipboard use in the completion path (grep + test).
4. Zero duplication/corruption over 100 consecutive accepts per backend.
5. No ghost suggestion left after focus/app change (observer test).

## Out of scope (later phases)

Constrained generation (F1), screen context (F2), style/contacts (F3), render polish (F4),
distribution (F5).
