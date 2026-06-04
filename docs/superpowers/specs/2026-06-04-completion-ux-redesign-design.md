# Wren — Completion quality & responsiveness redesign

**Date:** 2026-06-04
**Status:** Design — approved in brainstorming, pending written-spec review.
**Scope:** The inline-completion pipeline (helper generation + postprocessing + overlay + accept).
Builds on the existing `HelperCompletionProvider` / `LlamaSession` / `CompletionController` /
`CompletionPostprocessor` / `CompletionOverlayWindow` code already in `core/`.

## Problem (observed by the user)

Running Wren with a local model, the user reported:

1. **Incoherent / repeating suggestions.** Typing `1984 è un libro di ` suggested
   `il 1984 è un libro di George Orwell` — the model **restated the sentence** then continued. The
   existing echo-strip only matches an *exact* prefix, so the restated-with-"il" case slips through.
2. **Too slow / poor refresh rate.** Rapid `Tab` presses don't apply because the next suggestion
   isn't generated yet. The user wants it "quasi in tempo reale".
3. **Wrong space** between typed text and the accepted suggestion (sometimes glued, sometimes double).
4. **Language switching** (qwen drifts into Chinese). A blanket "reject CJK" is wrong — Wren must also
   serve Chinese users, so the filter must be *granular* (reject only unwanted language switches).
5. **`_` / punctuation** shown instead of a word; occasional repetition of the last word.
6. **Interruptions** — sometimes no suggestion appears.

Root cause of most "empty/garbage" seen during testing was a **flawed manual test** (piping many
requests at once triggered the helper's cross-process supersede, cancelling all but the last) plus the
earlier (now-fixed) request storm. In isolation, one request at a time, the local model produces
coherent Italian + English. So the work here is **quality polish + responsiveness**, not a model swap.

## Goals

- Fast, "near real-time" inline completion (≤ ~0.3–0.6 s after a pause; instant when pre-computed).
- Coherent suggestions: never restate the user's text; never emit a different script than the context.
- Correct join spacing on display and accept.
- Reliable: a suggestion appears whenever one reasonably can; rare, bounded fallback when not.
- Stays **on-device, private, light on RAM** (current model: qwen2.5-1.5b-instruct, ~1 GB).

## Non-goals (explicitly out of scope for this spec)

- **Injected "preview" ghost text inside the host app's field** — rejected: cannot style foreign text,
  removal on non-accept corrupts the field, fragile cross-app. We keep a floating overlay.
- **Top-k / tree speculation over unknown future typing** — the not-accepted branch is an open input
  space, not pre-computable as a single result. KV-cache warmth + mid-word mode cover the realistic
  gain. Revisit as v2 if needed.
- **Chromium / AX-blind apps** — tracked separately; needs caret-bounds work.

---

## A — Coherence / anti-repetition

**Primary (deterministic, no latency):** fuzzy overlap strip in `CompletionPostprocessor`.

- Normalize (lowercase, collapse runs of whitespace) both the **preContext tail** (last ~12 words) and
  the **suggestion**.
- Find the longest suffix of the normalized preContext that occurs as a (near-)prefix of the
  normalized suggestion — tolerating a small inserted leading token like "il". Cut the suggestion up
  to and including that overlap. `1984 è un libro di` + `il 1984 è un libro di George Orwell` →
  `George Orwell`.
- If after stripping the remainder is empty → treat as "no useful suggestion" (see retry below).

**Secondary (prevention):** keep the existing leading-meta / no-letter / repetition filters.

**Fallback (rare, bounded):** the engine loop is `generate → clean/validate → show`. If after cleaning
the result is empty/invalid, regenerate **at most once** (different seed). Never an unbounded loop —
that would cost multiple inferences and break the latency goal.

A prompt-level "don't repeat" instruction is **not** the primary mechanism (small models ignore it and
it forces the slower instruct mode). The deterministic strip is the guarantee.

## B — Responsiveness

### B1. Mid-word vs word-boundary modal generation

Decide generation length by the character before the caret (cheap, reliable — replaces the
spell-check `isMidWord` heuristic for this purpose):

- **Mid-word** (last char is a letter, no trailing space): generate **only the completion of the
  current word** — few tokens, stop at the first space. Lightweight; matches "finish the word I'm on".
- **Word boundary** (last char is whitespace/punctuation): generate the **next word(s)/phrase** up to
  the word budget.

This lightens compute while the user is "stuck" on a word and only does phrase prediction once the word
is complete.

### B2. Accepted-branch speculative pre-computation

When a suggestion `S` is shown for context `C`:
- In the background (idle helper time), pre-compute the completion for `C + S` (the "if the user
  accepts all of S" branch) and store it in `SuggestionCache` keyed by the resulting context.
- Reuses the helper's KV cache (shared prefix) → cheap.
- When the user finishes accepting `S`, the next suggestion is served from cache → instant, no wait.

The **not-accepted branch** (user keeps typing) is not pre-computed (open input space); the **warm KV
cache** keeps that path fast (only new characters are decoded).

### B3. Activation TTL

A shown suggestion stays valid for a short window (~300–500 ms) even if spurious AX
value/selection-changed events fire, so rapid `Tab` doesn't lose it. (Word-by-word `Tab` already walks
the same suggestion without re-generating — implemented.)

## C — Overlay rendering (kept floating, made better)

- **Font match:** read the focused field's font (family + size) via AX when available; render the ghost
  in the same font so it aligns with the text instead of looking like an external label. Fall back to
  the system font.
- **Adaptive readability:** use a native blur material (`NSVisualEffectView`, e.g. `.hudWindow`) behind
  the ghost so it reads on any background, light or dark — no Screen-Recording permission, no per-pixel
  sampling. (Optional future: 1px background sampling for exact contrast.)
- **Stable positioning:** anchor to the AX `caretRect`; reposition only when the suggestion text
  changes (no per-keystroke jitter).
- **Atomic insert on accept:** insert the accepted text in one operation (AX `setValue`/paste-style)
  with a char-by-char fallback for apps that don't support it — faster, cleaner than per-character.

### Style adaptation
- **Now:** bias suggestions toward the user's voice using the existing `StyleProfiler` (learned from the
  user's own history / accepted completions) — fast, private, no permission.
- **Later (opt-in):** screen-context style learning (OCR the surrounding text per app, cached and
  throttled — never per keystroke) behind a Screen-Recording opt-in.

## D — Granular language filter

- Detect the **dominant script** of the preContext (Latin / CJK / Cyrillic / …) via Unicode ranges.
- Reject a suggestion only if it is **entirely** a *different* script than the context (e.g. Latin
  context → all-CJK suggestion = reject). A foreign name mid-sentence is not rejected.
- **Prevention:** apply a sampler `logit_bias` that lowers the probability of CJK tokens when the
  context is Latin (and vice-versa), so the model rarely produces a wrong-script run in the first place
  → fewer rejections / fewer empties.

---

## Components touched

| File | Change |
|------|--------|
| `Core/Completion/CompletionPostprocessor.swift` | fuzzy overlap strip (A); keep filters; script-match reject (D) |
| `CompletionHelper/LlamaSession.swift` | mid-word vs phrase generation length (B1); language `logit_bias` (D); forced-content already done |
| `Core/Completion/HelperCompletionProvider.swift` | pass mid-word mode; accepted-branch pre-compute hook (B2) |
| `Core/Completion/CompletionController.swift` | mid-word detection by last char (B1); trigger accepted-branch pre-gen (B2); activation TTL (B3) |
| `Core/Completion/SuggestionCache.swift` | store/serve accepted-branch results (B2) |
| `UI/CompletionOverlayWindow.swift` | font-match + blur material + stable position (C) |
| `Accessibility/AccessibilityBridge.swift` | read focused-field font (C); atomic insert on accept (C) |

## Data flow (per keystroke pause)

```
keystroke → RealtimeMonitor AX observer → CompletionController.textChanged()
  → debounce (~140 ms) → requestSuggestion():
      pid (frontmost) → AX context (preContext, caretRect, field font)
      mid-word? → choose generation length
      cache hit (accepted-branch)? → show instantly
      else → CompletionEngine → HelperCompletionProvider → LlamaSession
              (logit_bias by script; generate; trim; forced-content fallback)
      → CompletionPostprocessor.clean (fuzzy strip, script reject, filters)
      → valid? show (overlay: font-match + blur, anchored)         ┐
                + kick off accepted-branch pre-compute (background) ┘
      → invalid after clean? at most 1 regen, else show nothing
Tab  → accept next word (walk S in memory, re-anchor)   ;  \ → accept full (atomic insert)
```

## Testing

- `CompletionPostprocessor` unit tests: fuzzy strip ("1984" case, "il"-prefixed restate), script-match
  reject (Latin vs CJK, mixed), repetition, spacing (mid-word/boundary/double-space).
- `LlamaSession` mid-word vs phrase length (token budget + stop-at-space).
- Manual: **one request at a time** (sequential) — never pipe many at once (triggers cross-process
  supersede and mis-measures quality).

## Sequencing

1. **A + D** (postprocessing: fuzzy strip, script match, logit-bias) — highest quality impact, low risk.
2. **B1** (mid-word mode) — speed + relevance.
3. **B2 + B3** (accepted-branch pre-compute + cache + TTL) — responsiveness.
4. **C** (overlay font-match + blur + atomic insert) — native feel.

Each step independently testable and shippable.
