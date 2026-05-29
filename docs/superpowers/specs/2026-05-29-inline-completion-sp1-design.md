# SP1 — Inline Completion Engine (Cotypist-parity) — Design Spec

**Date:** 2026-05-29
**Status:** Approved design, pre-implementation
**Author:** Eugenio + Claude
**Part of:** Cotypist-parity initiative (SP1 → SP2 → SP3 → SP4)

## Goal

Add system-wide **predictive inline completion** to Parrot: as the user types in any text
field, Parrot shows greyed "ghost" suggestion text at the caret; pressing **Tab** inserts the
full suggestion, a separate shortcut inserts one word (partial accept). On-device, low-latency,
per-app controllable. This is the foundation the rest of the Cotypist-parity work builds on.

### Non-goals (SP1)
- No rich context gathering beyond the current text field (clipboard/screenshot context = **SP2**).
- No automatic typo correction while typing / emoji completion (**SP3**).
- No snippet/abbreviation expansion or custom dictionary (**SP4**).
- No new inference architecture: SP1 uses the existing `llama-server` subprocess (see ADR below).

## Architecture Decision (ADR): keep `llama-server`, do NOT link `libllama` in-process

**Decision:** SP1 runs inference through the existing bundled `llama-server` subprocess, using its
native `/infill` and `/completion` endpoints with `cache_prompt`, a dedicated warm slot, streaming,
and request cancellation. We do **not** link `libllama` into the app process.

**Rationale (priority = solidity / long-term reliability):**
- `llama-server` is upstream-maintained and crash-isolated: an inference crash never takes down
  Parrot. A hand-rolled `libllama` C↔Swift bridge is code *we* own and maintain across every
  llama.cpp update — more surface, less reliable.
- Features ≠ architecture: every Cotypist feature is reachable on the server backend. In-process is
  only a latency optimization, not a product capability.
- One inference engine, not two. Avoids the "two code paths" maintenance trap.
- On an M2 Pro with a ~2B model, `cache_prompt` + a warm slot makes localhost HTTP overhead
  (~1–5ms) negligible against inference time.

**Escape hatch (measured, not speculative):** SP1 ships a latency benchmark. If end-to-end
keystroke→ghost latency exceeds the target on target hardware, we introduce `libllama` in an
**isolated XPC helper process** (preserving crash isolation) — only then, and backed by numbers.

## The hard part: ghost text inside arbitrary apps

You cannot draw grey text inside another app's text field via Accessibility. Solution (same shape
as Cotypist): a borderless, non-activating **overlay window** that draws the suggestion at the caret
screen position, obtained from `AccessibilityBridge.boundsForRange(_:pid:)` (already implemented via
`kAXBoundsForRangeParameterizedAttribute`). Tab is intercepted with a `CGEventTap` (new capability —
none exists in the codebase today) and swallowed when a suggestion is visible.

## Components (isolated units)

### 1. `CompletionEngine` — `Core/Completion/CompletionEngine.swift` (actor)
- `suggest(preContext: String, postContext: String, language: String) async -> String?`
- Builds an `/infill` request (`input_prefix` = preContext, `input_suffix` = postContext) with
  `n_predict = maxCompletionLength` (default 8 tokens), `cache_prompt: true`, `stream: true`,
  temperature low (~0.2). Stops at first newline / sentence boundary for "short" completions.
- Cancellable: the in-flight `URLSession` task is cancelled when a newer keystroke arrives.
- *Depends on:* `ServerManager` (warm slot), a new `CompletionRequest`/endpoint helper.
- *Does NOT* go through `RequestQueue` (that serialises correction jobs); completions use their own
  lightweight path with a single reused slot so a stale completion never blocks a correction.

### 2. Server endpoint support — `Core/Completion/LlamaCompletionClient.swift`
- POST to `http://127.0.0.1:<port>/infill` (fallback `/completion` with a prefix-only prompt for
  apps where postContext is unavailable).
- Streaming SSE parse (reuse `SSEStreamingEngine` if compatible, else a thin parser).
- `cache_prompt: true` so consecutive completions sharing a prefix reuse the slot KV cache.
- Verify the bundled `llama-server` build exposes `/infill`; if not, rebuild flag in `build-app.sh`.

### 3. `CompletionController` — `Core/Completion/CompletionController.swift` (`@MainActor`)
Orchestrates the live loop. Owns suggestion state and the debounce.
- Subscribes to text-change events (extend `RealtimeMonitor`; completion uses a **shorter** debounce
  ~400ms vs the existing 800ms correction debounce — configurable).
- On debounce fire: read pre/post context + caret bounds via `AccessibilityBridge`, call
  `CompletionEngine.suggest`, and if non-empty show the overlay.
- Cancels/clears on: caret move, focus change, Escape, any non-Tab keystroke, app excluded.
- Guards: min preContext length, skip in password fields (`AXSecureTextField`), skip excluded apps.

### 4. `CompletionOverlayWindow` — `UI/CompletionOverlayWindow.swift`
- `NSPanel`, `.nonactivatingPanel`, `ignoresMouseEvents = true`, `level = .statusBar`,
  `collectionBehavior` = canJoinAllSpaces + stationary. Borderless, transparent.
- Draws the ghost suggestion (grey, matching approximate font size) at the caret rect; partial-accept
  word boundary subtly marked.
- Positioned from `boundsForRange` screen coordinates; hides if bounds are `.zero`/offscreen.

### 5. `TabInterceptor` — `Shortcuts/TabInterceptor.swift` (`CGEventTap`)
- A `CGEventTap` on `keyDown`. When a suggestion is visible:
  - **Tab** → swallow the event, insert the full suggestion via `AccessibilityBridge`, clear overlay.
  - **partial-accept shortcut** (default ⌘→ or Cotypist-style) → insert first word only, re-suggest.
  - **Escape** → clear overlay, do not swallow.
- When no suggestion is visible, pass all events through untouched.
- Requires Accessibility permission (already requested by Parrot). Tap re-armed on disable/timeout.
- *Safety:* the tap callback is minimal and never blocks; heavy work is dispatched off the tap.

### 6. Insertion — reuse `AccessibilityBridge.replaceSelectedText` / value-set path
Insert at caret. Prefer `AXValue` insertion; fall back to the existing clipboard-paste path (with
clipboard save/restore already implemented) for apps that reject direct insertion.

### 7. Settings & per-app control — extend existing
- New `PreferencesStore` keys: `inlineCompletionEnabled` (default true), `maxCompletionLength` (4),
  `completionDebounceMs` (400), `partialAcceptShortcut`, `completionUserPrompt` (personalization
  string, like Cotypist's userPrompt).
- Per-app enable/disable reuses the **exclusions / AppRules** system (default on, excludable).
- A `CompletionTab` (or a section in an existing tab) for the toggles + user prompt. (UI polish can
  trail into a later pass; functional toggles ship in SP1.)

## Data Flow

```
User types  →  RealtimeMonitor text-change event  →  CompletionController debounce (~400ms)
   →  AccessibilityBridge: read preContext, postContext, caret bounds (boundsForRange)
   →  CompletionEngine.suggest(pre, post, lang)  →  llama-server /infill (cache_prompt, stream, n_predict=8)
   →  non-empty?  →  CompletionOverlayWindow.show(ghost, at: caretRect)

User presses Tab (suggestion visible)
   →  TabInterceptor swallows Tab  →  AccessibilityBridge insert(suggestion)  →  overlay clear
User presses any other key / moves caret / changes focus
   →  CompletionController cancels in-flight suggest + clears overlay
```

## Latency Benchmark (ship gate)

A dev-only measurement harness logs the pipeline stages:
`keystroke → debounce end → context read → first token → ghost visible`.
- **Target:** perceived ghost-visible latency **< ~150 ms** after the typing pause on M2 Pro / E2B.
- Measured with a warm slot + `cache_prompt`. If the median exceeds target, open the in-process
  XPC-helper escalation (separate spec); do not block SP1's other parts on it.

## Error Handling
- Server not running / slow → no overlay (silent); never blocks typing.
- `boundsForRange` returns `.zero` / app lacks AX text bounds → suppress overlay (don't guess a spot).
- Secure/password fields → never suggest.
- `CGEventTap` disabled by the system (timeout) → auto re-enable; if permission lost, disable feature
  gracefully and surface a one-time notice.
- Insertion failure → fall back to clipboard-paste path; if that fails, clear overlay, no-op.
- All completion work is cancellable and must never delay the user's keystrokes.

## Testing
- `CompletionEngine`: request shaping (infill prefix/suffix, n_predict, cache_prompt), stop conditions,
  cancellation (newer request supersedes older), empty-result handling. (Stub the HTTP client.)
- `LlamaCompletionClient`: SSE parse of partial tokens; `/infill`→`/completion` fallback.
- `CompletionController`: debounce coalescing, clear-on-keystroke/focus-change/escape, secure-field
  and excluded-app guards.
- `TabInterceptor`: swallow Tab only when suggestion visible; pass-through otherwise; partial vs full.
- Overlay positioning math from `boundsForRange` (coordinate conversion).
- Latency harness produces stage timings (smoke test, not asserted thresholds in CI).

## Risks
- **Ghost rendering fidelity** across apps (font/size/baseline) — overlay is approximate; acceptable,
  matches Cotypist's known limitation; per-app AX quirks documented as discovered.
- **CGEventTap** is privileged and global; bugs could swallow keystrokes. Mitigate: only swallow Tab,
  only when a suggestion is visibly shown, with a hard kill-switch and auto-pass-through on any error.
- **Per-app AX compatibility** (Electron, terminals) — some apps don't expose caret bounds; feature
  degrades to "no suggestion" there, never breaks typing.

## Build-order note
SP1 must land and prove stable (latency gate + no-keystroke-loss) before SP2 (context) layers on,
because SP2/SP3/SP4 all reuse SP1's overlay + insertion + event-tap channel.
