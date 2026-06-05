# Focus Mode Completion — Design Spec

Date: 2026-06-05
Status: approved, ready for implementation plan
Scope: P0 + P1 (make the write→count→record→streak loop fully work). P2 options
(blindwrite, forward-only, kiosk, soundscapes) explicitly deferred.

---

## Background

Focus Mode is ~70% scaffolded but its core loop is broken. The feature lets a user
start a timed writing session during which Wren's AI (completion + correction) is
silenced (raw draft), tracks words written, records the session, and maintains a
daily streak with celebration feedback.

Existing files (already compile, on branch `feat/wren-onboarding`, uncommitted):

- `Core/FocusMode.swift` — state machine (off / rawDraft / session). OK.
- `Core/FocusTimer.swift` — 1 Hz countdown. Has a resume bug.
- `Core/FocusStatsStore.swift` — JSON-persisted stats + streak. Streak freeze hardcoded.
- `UI/FocusOverlayWindow.swift` — floating timer overlay. Stop/pause wiring broken.
- `UI/FocusSessionView.swift` — setup / active / recap panel content. Record flow circular.
- `UI/FocusTab.swift` — settings + `FocusSessionPanel`. Panel ownership fragile.
- `UI/FocusCelebration.swift` — toast / sound / streak milestone. OK; called at wrong time.
- Modified: `App/Constants.swift`, `Infra/PreferencesStore.swift`,
  `Core/Completion/CompletionController.swift`, `Core/RealtimeMonitor.swift`,
  `UI/MenuBarView.swift`, `UI/DashboardTab.swift`, `UI/SettingsView.swift`.

### Defects this spec fixes

1. **Word counting does not exist.** `recordSession(words: stats.todayWords, …)` is
   circular — always records 0. Nothing measures words typed during a session. The
   headline metric ("words in focus"), heatmap, and celebration are all dead.
2. **`FocusTimer.resume()` restarts the full duration.** It rebuilds `.running` with
   `startTime: .now` and `dur = elapsed + remaining` (= original duration), so after
   resume the timer runs the entire original duration again from zero.
3. **Overlay X button** calls `FocusOverlayWindow.shared.hide()` but not `timer.stop()`,
   so the timer keeps ticking in the background after the overlay is dismissed.
4. **Overlay pause button** has no resume state — always shows the pause icon.
5. **Recording flow is wrong.** `finish()` fires `FocusCelebration` with `words=0`
   before the user records anything; recap's "Record & continue" then records
   `todayWords` (still 0). Double / incorrect.
6. **`FocusSessionPanel` ownership is fragile.** Created as a local `let panel` in
   `MenuBarView`, it can deallocate; the recap is never surfaced if the panel was
   closed when the timer finishes.
7. **Streak freeze is hardcoded** to `1` in `FocusStatsStore`, ignoring the
   `focusStreakFreeze` preference exposed in `FocusTab`.
8. **P2 toggles lie.** forward-only, blindwrite, kiosk, background-sound are shown as
   active settings but have no effect.

---

## Goals

- A real focus session counts the words the user types, in any AX-capable app.
- Timer pause/resume preserves remaining time.
- A single, correct stop → recap → record → celebrate flow.
- Streak respects the configurable freeze preference.
- The settings UI does not claim features that are not implemented.

## Non-goals (deferred to a later cycle)

- Blindwrite (text fades while typing).
- Forward-only (no backspace).
- Kiosk mode (no escape).
- Background soundscapes (audio playback + assets).
- Per-week freeze accounting (the simple "freezes-in-chain ≤ limit" rule stays).

---

## Architecture

### New component: `FocusWordCounter`

`@MainActor final class FocusWordCounter: ObservableObject`, owned by `FocusTimer`.

State:
- `@Published private(set) var wordsWritten: Int = 0`
- `private var lastCount: Int = 0`
- `private var pollTask: Task<Void, Never>?`

API:
- `func start()` — capture baseline, begin polling.
- `func stop()` — cancel polling. `wordsWritten` retains its final value.
- `func reset()` — zero everything (called by `start`).

Behavior:
- On `start()`: read the focused element's plain text via the AX bridge, set
  `lastCount = wordCount(text)`, `wordsWritten = 0`.
- Poll loop: every 2 seconds (`Task.sleep(for: .seconds(2))`), read the focused text
  and compute `newCount = wordCount(text)`, then:
  - `delta = newCount - lastCount`
  - if `delta > 0` → `wordsWritten += delta`; `lastCount = newCount` (user wrote)
  - if `-REBASE_THRESHOLD <= delta <= 0` → `lastCount = newCount` (backspace / small edit, no subtraction)
  - if `delta < -REBASE_THRESHOLD` → `lastCount = newCount` (field/app switch — rebase, do not subtract)
  - `REBASE_THRESHOLD = 5` words.
- If a poll read fails (no focused element / no AX value), skip that tick without
  changing state.

The PID used for reads comes from `AccessibilityBridge.shared.lastKnownFrontAppPID()`
each tick (so switching the front app naturally rebases via the threshold rule).

Word counting helper (shared, testable, pure):
```swift
func wordCount(_ s: String) -> Int {
    s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
}
```
Lives as a `static` on `FocusWordCounter` (or a small free function in the same file)
so it can be unit-tested without AX.

### AX bridge addition

Add to `AccessibilityBridge` (actor):
```swift
func focusedPlainText(pid: pid_t) async -> String?
```
Reads the focused element of `pid` (reuse `withFocusedElement`) and returns its
`kAXValueAttribute` as `String`, or `nil` if unavailable. Mirror the existing
`extractText(from:)` logic; expose via the actor's isolated API. Add the signature to
`AXBridgeProtocol` only if the protocol is used to reach this call site; otherwise call
the concrete `AccessibilityBridge.shared` directly (the counter is MainActor, the bridge
is an actor — call is `await`).

### `FocusTimer` changes

- Own a `let wordCounter = FocusWordCounter()` (or reference `FocusWordCounter.shared`;
  prefer an instance owned by the timer for clear lifecycle).
- `start(durationMinutes:)` → also `wordCounter.start()`.
- `pause()` → `wordCounter.pause()` (cancels the poll task, keeps `wordsWritten`).
- `resume()` → `wordCounter.resumeCounting()` (re-baselines `lastCount` to the current
  field and restarts the poll task without zeroing `wordsWritten`).
  So `FocusWordCounter` exposes three lifecycle calls: `start()` (reset + baseline +
  poll), `pause()` (stop poll, keep count), `resumeCounting()` (re-baseline + poll, keep
  count), and `stop()` (stop poll, keep final count).
- **Fix resume():** rebuild `.running(durationSeconds: dur, startTime: Date().addingTimeInterval(-Double(elapsed)))`
  where `dur = elapsed + remaining`. Remove unused `pauseElapsed` / `pauseRemaining`
  fields (replace with the values carried in the `.paused` case).
- `stop()` → `wordCounter.stop()`, set `.idle`, `FocusMode.shared.endSession()`.
- `finish()` → `wordCounter.stop()`, set `.finished`, `FocusMode.shared.endSession()`,
  then surface the recap (see flow). Do **not** call `FocusCelebration` here.
- Expose `var wordsWritten: Int { wordCounter.wordsWritten }`.

### Stop / recap / record flow

Single source of truth, no duplicate recording:

1. **Timer expires** → `finish()` sets `.finished`, stops the counter, ends the focus
   session, and calls `FocusSessionPanel.shared.show()` so the recap is visible even if
   the panel was closed. The overlay hides itself when state becomes `.finished`
   (overlay observes `FocusTimer.timerState`).
2. **Recap "Record & continue"** → `stats.recordSession(words: timer.wordsWritten,
   minutes: timer.elapsedSeconds / 60, mood: selectedMood)`, **then**
   `FocusCelebration.shared.celebrateSessionComplete(words: timer.wordsWritten,
   minutes: timer.elapsedSeconds / 60)`, then `timer.stop()` and dismiss panel + overlay.
3. **Recap "Discard"** → `timer.stop()`, dismiss; no record, no celebration.
4. **User ends early (overlay X or active-view "End session")** → `timer.stop()`.
   If `timer.wordsWritten > 0` and at least ~1 minute elapsed, transition to `.finished`
   and show recap (so early-but-productive sessions can still be recorded); otherwise go
   straight to `.idle` and dismiss. Decision rule lives in one place
   (`FocusTimer.endEarly()` helper) to avoid divergence between overlay and panel.

### Overlay pause/resume

`FocusOverlayContent` pause button:
- if `timer.isPaused` → icon `play.fill`, action `timer.resume()`
- else → icon `pause.fill`, action `timer.pause()`

Overlay X button → `timer.endEarly()` (not bare `hide()`).
Overlay hides itself on `.finished` / `.idle` via observation of `timer.timerState`.

### `FocusSessionPanel` ownership

Convert to a singleton: `static let shared = FocusSessionPanel()`, private init.
- `MenuBarView` → `FocusSessionPanel.shared.show()`.
- `FocusTimer.finish()` / `endEarly()` (when recap needed) → `FocusSessionPanel.shared.show()`.
- Remove the local-`let` creation in `MenuBarView`.

### Streak freeze wired to preference

In `FocusStatsStore.recomputeStreak()`, replace the constant
`private let streakFreezeLimit = 1` with a read of
`PreferencesStore.shared.focusStreakFreeze` at recompute time (clamped to `0...7`).

### Honest P2 settings

In `FocusTab`, the four unimplemented controls (forward-only, blindwrite, kiosk,
background sound) are shown `.disabled(true)` with a "(coming soon)" suffix in their
labels. The preferences and `Constants` keys stay (harmless, used later).

---

## Data flow (happy path)

```
MenuBar "Start focus session"
  → FocusSessionPanel.shared.show()  (setup view)
  → user picks duration + mood, taps Start
      → FocusTimer.start(minutes)            // sets FocusMode .session ⇒ isRawDraft
          → FocusMode.startSession            // CompletionController + RealtimeMonitor gated off
          → FocusWordCounter.start()          // baseline from focused field
      → FocusOverlayWindow.shared.show()      // live timer + words + streak
  ... user writes in their own app; counter polls every 2s ...
  → timer expires → FocusTimer.finish()
      → counter.stop(); state .finished; FocusMode.endSession()
      → FocusSessionPanel.shared.show()       // recap with real words
  → recap "Record & continue"
      → FocusStatsStore.recordSession(words, minutes, mood)
      → FocusCelebration.celebrateSessionComplete(words, minutes)
      → timer.stop(); dismiss panel + overlay
```

---

## Testing

### Unit (XCTest, no AX)
- `wordCount`: empty string → 0; single word → 1; multiple spaces / tabs → correct;
  newlines → counted as separators; leading/trailing whitespace → ignored; unicode /
  accented words → counted.
- `FocusWordCounter` delta logic via an injectable text source (closure returning the
  "current text" instead of the AX bridge): writing increases `wordsWritten`; small
  backspace (≤ threshold) does not decrease it; large drop (field switch) rebases
  without subtracting; failed read (nil) leaves state unchanged.
- `FocusTimer` pause/resume: after `start(1 min)`, advance, `pause()`, `resume()` →
  `remainingSeconds` continues from where it paused (does not reset to full duration).
- `FocusStatsStore` streak: with `focusStreakFreeze = 0`, a one-day gap breaks the
  streak; with `= 1`, a single gap is bridged; `longestStreak` updates monotonically.

To make `FocusWordCounter` and `FocusTimer` testable, inject the text source and a
clock/elapsed provider rather than calling `AccessibilityBridge.shared` / `Date()`
directly inside the loop. Keep the production defaults wired to the real bridge.

### Manual
- Real session in TextEdit: type a paragraph → overlay word count climbs → recap shows
  the right count → "Record & continue" → DashboardTab "Words in focus" and the week
  heatmap update; streak shows 1 day.
- Pause mid-session, wait, resume → countdown resumes correctly, words keep counting.
- Stop early via overlay X with words written → recap appears; with no words → dismiss.
- Confirm completion + correction stay silenced during the session and resume after.

---

## Files

New:
- `Core/FocusWordCounter.swift`

Modified:
- `Core/FocusTimer.swift`
- `Core/FocusStatsStore.swift`
- `Accessibility/AccessibilityBridge.swift` (+ `Accessibility/AXBridgeProtocol.swift` if the protocol is the call path)
- `UI/FocusOverlayWindow.swift`
- `UI/FocusSessionView.swift`
- `UI/FocusTab.swift`
- `UI/MenuBarView.swift`

Tests:
- `Tests/FocusModeTests.swift` (new)

---

## Risks

- **AX text unavailable in some apps** (certain Electron/web views) → word count stays
  flat for those apps. Acceptable; the counter degrades gracefully (no crash, just 0
  delta). Documented as a known limitation.
- **2s poll vs. AX read cost** → reads are cheap single-attribute fetches; 0.5 Hz is far
  below the completion path's rate. No expected perf impact.
- **Front-app switching during a session** → handled by the rebase-on-large-drop rule;
  words typed in a different app during the session still count.
