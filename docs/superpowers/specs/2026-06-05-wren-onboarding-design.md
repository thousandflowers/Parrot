# Wren Onboarding & Tone Capture — Design

**Date:** 2026-06-05
**Status:** Approved (brainstorming) → ready for implementation plan
**Branch target:** core submodule, `feat/wren-foundations` lineage (currently `main`)

## Problem

Parrot and Wren ship from one codebase as two apps, selected by bundle id via `AppMode`.
Settings (`SettingsView`) and the menu bar (`MenuBarView`/`MenuBarParrot`) are already mode-gated.
**The onboarding is not.** `AppDelegate.applicationDidFinishLaunching` calls
`OnboardingController.shared.showIfNeeded()` unconditionally, and `OnboardingView` is 100% Parrot:
window title "Initial Setup — Parrot", 🦜 emoji, "Welcome to Parrot", grammar features, grammar
shortcuts (⌘⇧E), a fake hardcoded grammar demo, and an Accessibility permission step.

A Wren user therefore sees the wrong product. Concretely (audit findings):

- **O1** Onboarding not mode-gated → Wren shows Parrot's entire flow.
- **O2** Wrong permission: Wren needs **Input Monitoring** (`IOHIDCheckAccess`/`IOHIDRequestAccess`
  for `TabInterceptor`'s key-swallowing tap) + optional Screen Recording. Onboarding requests
  Accessibility only.
- **O3** No tone/style capture. Completion personalization is cold at first run; `StyleProfiler`
  is Parrot-only (learns from rejected grammar corrections).
- **O4** Model download is disjoint: `OnboardingModelDownloader` exists but the flow does not run it
  for Wren; instead a raw `NSAlert` ("Nessun modello installato") fires post-launch.
- **O5** The "Try it" step shows a fake hardcoded grammar correction, not a live completion.

Branding leaks (in scope, cheap): status item label hardcoded `"Parrot menu"` /
`"Open the Parrot correction menu"` (`AppDelegate.swift:141-142`); onboarding window title hardcoded
"…Parrot".

## Goal

A Wren-native first-run flow that:
1. Shows the right product (mode-gated).
2. Requests the right permission (Input Monitoring; Screen Recording optional).
3. Captures the user's writing tone (examples + paste) and seeds personalization from day one.
4. Starts the model download **in the background at step 0** so the wait is masked by the
   interactive steps.
5. Ends with a live completion demo (or a graceful "almost ready" if the download is still running).

## Non-goals

- Splitting the shared core into two repos (deliberately shared: mmap weights, single fix surface).
- Reworking the completion engine, model catalog, or learning store internals — all reused as-is.
- Touching the Parrot onboarding behavior (only extracted/renamed, not redesigned).

## Key existing plumbing (reused, not rebuilt)

- `CorpusLearner.learn(from: String)` — extracts `(context-key → continuation)` pairs from user text
  and seeds them confident. Also `learn(fromFiles:)`.
- `CompletionLearningStore.seed(entries, accepts:)` — idempotent, additive (`accepts = max`),
  variable-order n-gram keys; serves learned completions instantly with no model call.
- `StyleProfile` (in `CompletionLearningStore`) — writing fingerprint; `.descriptor` is a ~2-line
  prompt hint (`styleDescriptor()`), gated at `totalSentences >= 3`.
- `ModelManager.recommendedModels()` + `downloadModelWithProgress(from:expectedSHA256:)`
  (`AsyncThrowingStream<DownloadProgress, Error>`).
- `ModelCatalog.recommended(ramGB:language:)` — RAM-aware model recommendation.
- Input Monitoring: `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` (check),
  `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` (request) — already used in
  `Shortcuts/TabInterceptor.swift:35-38`.

## Architecture (Approach 2: separate view + shared scaffold)

```
OnboardingController                    (exists) → mode-gating: picks root view
 ├─ OnboardingScaffold        (NEW)  shared chrome: bottom bar, step dots, container, Back/Next/Skip
 ├─ ParrotOnboardingView      (= current OnboardingView, renamed, unchanged behavior)
 └─ WrenOnboardingView        (NEW)  composes Scaffold + Wren steps
      ├─ ModelDownloadCoordinator (NEW, @Observable) — shared download state across steps
      └─ steps: Welcome / Permission / Tone / ScreenContext? / Ready
```

Decisions:
- `OnboardingController.showIfNeeded()` picks the root view from `AppMode.current`.
  **Per-mode completion key:** `hasCompletedOnboarding_wren_v1` (separate from Parrot's
  `hasCompletedOnboarding_v2`) so an existing Parrot user still sees the Wren onboarding.
- `ModelDownloadCoordinator` lives at `WrenOnboardingView` level (not inside a single step) so the
  download starts at step 0 and progress survives step changes. It is the unit that wraps
  `downloadModelWithProgress`. Pure/injectable for tests (takes a download-stream provider).
- The current `OnboardingModelDownloader` (button-driven view) is removed; its logic folds into the
  Coordinator.
- Why not "branch inside the existing 732-line `OnboardingView`": the file is already a code smell;
  a separate view keeps Wren and Parrot independent and the units small.

## Flow & states

| Step | Content | Download | Permission |
|------|---------|----------|------------|
| 0 Welcome | Wren identity (no 🦜/grammar): "inline completion, Tab to accept". RAM-detect → `ModelCatalog.recommended`. **Kick off background download.** | starts | — |
| 1 Permission | Explain + `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)`. Poll `IOHIDCheckAccess` to auto-advance (same pattern as the existing `AccessibilityStep`). | continues | Input Monitoring |
| 2 Tone | Guided examples (default) + expandable "or paste your own text" → instant CPU seed. Skippable. | continues | — |
| 3 Screen context (optional) | Explain reading context above the caret; button requests Screen Recording. Skippable. | continues | Screen Recording (optional) |
| 4 Ready | If download done → **live completion demo** (type, see ghost text). Else → progress bar + "you can start, ready soon". | finishes / continues in bg | — |

- The download progress bar is **always visible** in the scaffold footer until complete.
- "Finish" is never blocked by the download: if unfinished, the window closes on completion and the
  download proceeds in `ModelManager` (not tied to the window lifetime).

## Tone capture (step 2) — detail

Two modes in one step, examples as default:

**Examples mode (default, visible):**
- 2–3 sentence openers shown in editable fields; the user finishes each in their own voice.
  E.g. a field pre-filled with an opener, cursor at the end, user continues.
- **No hardcoded lists** ([[feedback_no_hardcoded_lists]]): NOT a per-app/per-language matrix of
  phrases. Instead a small set of neutral openers via `String(localized:)` (translation files, not
  `if/else` in code). Language comes from the system locale (no typed text exists yet at onboarding).
- On completion, the full sentence (opener + continuation) is passed to `CorpusLearner.learn(from:)`
  (extracts context→continuation pairs + seeds) and updates `StyleProfile`.

**Paste mode (expandable "or paste your own text"):**
- `TextEditor`; on confirm → `CorpusLearner.learn(from: pasted)`. Richer signal (many pairs + full
  fingerprint).

**Output (both modes):**
- `CompletionLearningStore.seed(entries)` → instant day-1 completions.
- `StyleProfile` updated → `descriptor` injected into the model prompt.
- Honest UI feedback: "Learned N patterns from your style" where N is the return of `seed`/`learn`.
  If N=0: "I'll use this as a hint" with no number (no false claims).
- Step has a Skip — tone capture is a bonus, never blocks.

## Backend wiring

- No new engine. Reuse `CorpusLearner`, `CompletionLearningStore.seed`, `StyleProfile`.
- **Gap C2 (StyleProfile not injected into completion prompt):** during planning, locate where
  `CompletionEngine`/`PromptEngine` builds the completion prompt and ensure
  `CompletionLearningStore.styleDescriptor()` is included when non-empty. If missing, add it (part of
  O3). Confirm by reading the prompt builder — do not assume.
- **Background download:** `ModelDownloadCoordinator` calls
  `ModelManager.shared.downloadModelWithProgress(...)`; on `.complete` sets
  `PreferencesStore.completionModelID` + `serviceType = .local` and triggers
  `CompletionEngine.warmup()`.
- **Recommended model:** `ModelCatalog.recommended(ramGB:language:)`. Note from prior tuning: qwen
  0.5b/1.5b are weak for completion; during planning verify the Wren recommendation does not push a
  too-weak model (completion recommendation may differ from correction recommendation).

## Error handling & edge cases

- **Download fails (network/SHA):** Coordinator exposes `errorMessage`; Ready shows "Download failed
  — retry / download later from Settings → Models". App usable; completion off until a model exists
  (existing `NSAlert` kept only as a fallback if the user skips everything).
- **Input Monitoring denied:** step does not block; Ready warns "Wren needs Input Monitoring to work,
  enable it in System Settings" with a direct link. Onboarding still completes.
- **User skips everything (Skip):** `completedKey` set, download cancelled, no tone capture. App
  works once model + permission exist.
- **Local model already present** (`localModels()` non-empty): step 0 does not restart the download,
  shows "model already ready".
- **Onboarding reopened from Settings:** idempotent; no re-download if present; tone seed additive
  (`seed` dedups, `accepts = max`).
- **Window closed mid-download:** download proceeds (lives in `ModelManager`, not the view);
  `completedKey` set only at end of flow or explicit Skip.
- **Low RAM:** `recommended(ramGB:)` already picks a small model; no crash.

## Branding fixes (in scope)

- `AppDelegate.swift:141-142`: status item label/help → use `AppMode.current.displayName` instead of
  hardcoded "Parrot".
- Onboarding window title → `AppMode.current.displayName`.

## Testing (TDD, pure/injectable units — same discipline as Phase 0)

- `ModelDownloadCoordinator` with a stub `ModelManager`/fake stream → states
  downloading→verifying→complete→error, cancel, no-restart-when-present.
- Tone-capture logic extracted out of the View (pure): "opener + continuation → seed entries +
  StyleProfile update". Assert N patterns; N=0 → no claim. Reuse existing `CorpusLearner`/
  `CompletionLearningStore` tests.
- `OnboardingController` mode-gating: `.wren` → WrenView, `.parrot` → ParrotView; per-mode
  `completedKey`.
- StyleProfile → prompt injection (C2): test the prompt builder includes `styleDescriptor()` when
  non-empty.
- Views: smoke only (not logic) — no fragile snapshots.

## Out of scope / follow-ups (from the wider audit)

- C1 model-choice guidance refinements beyond `recommended()`.
- Deeper personalization wiring (CorpusLearner from a folder in Settings already exists).
- Other branding sweeps beyond the two leaks above.
</content>
</invoke>
