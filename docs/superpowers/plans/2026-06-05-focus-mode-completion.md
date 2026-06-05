# Focus Mode Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Wren's Focus Mode loop (write → count words → record → streak) actually work, fixing the dead word-counter, broken timer resume, and incorrect record/celebrate flow.

**Architecture:** A new `FocusWordCounter` polls the focused field via Accessibility every 2s and accumulates positive word-count deltas (rebasing on field switches). `FocusTimer` owns the counter, and a single stop→recap→record→celebrate flow replaces the current circular one. Pure cores (word count, delta processing, streak, resume-time) are extracted so they unit-test without AX or real time.

**Tech Stack:** Swift, SwiftUI, AppKit, XCTest, Accessibility (AXUIElement). Build: `swift build`. Test: `swift test`. Repo root for these paths: `core/` (the submodule). Run all commands from `core/`.

---

## File Structure

New:
- `Core/FocusWordCounter.swift` — word counting: pure `wordCount`, pure `processReading`, AX poll loop, lifecycle (start/pause/resumeCounting/stop).
- `Tests/FocusModeTests.swift` — unit tests for the pure cores.

Modified:
- `Accessibility/AccessibilityBridge.swift` — add `focusedPlainText(pid:)`.
- `Core/FocusTimer.swift` — fix resume, own the counter, `endEarly()`, `finish()` no longer celebrates.
- `Core/FocusStatsStore.swift` — extract pure `computeStreak`, wire freeze preference.
- `UI/FocusSessionView.swift` — correct recap/record/celebrate flow.
- `UI/FocusTab.swift` — `FocusSessionPanel` singleton; disable P2 toggles.
- `UI/MenuBarView.swift` — use `FocusSessionPanel.shared`.
- `UI/FocusOverlayWindow.swift` — pause/resume toggle, X→`endEarly()`, auto-hide.

---

## Task 1: Word-count + delta pure cores

Pure, synchronous, no AX — the heart of the counter, fully testable.

**Files:**
- Create: `Core/FocusWordCounter.swift`
- Test: `Tests/FocusModeTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/FocusModeTests.swift`:

```swift
import XCTest
@testable import Parrot

@MainActor
final class FocusWordCountTests: XCTestCase {

    // MARK: - wordCount

    func testWordCount_empty() {
        XCTAssertEqual(FocusWordCounter.wordCount(""), 0)
        XCTAssertEqual(FocusWordCounter.wordCount("   \n  "), 0)
    }

    func testWordCount_singleAndMultiple() {
        XCTAssertEqual(FocusWordCounter.wordCount("hello"), 1)
        XCTAssertEqual(FocusWordCounter.wordCount("hello world"), 2)
        XCTAssertEqual(FocusWordCounter.wordCount("  hello   world  "), 2)
        XCTAssertEqual(FocusWordCounter.wordCount("a\tb\nc"), 3)
    }

    func testWordCount_unicode() {
        XCTAssertEqual(FocusWordCounter.wordCount("caffè è pronto"), 3)
    }

    // MARK: - processReading delta logic

    func testProcessReading_writingAccumulates() {
        var c = FocusWordCounter()
        c.baseline(count: 2)            // field already had 2 words
        c.processReading(count: 5)      // wrote 3 more
        XCTAssertEqual(c.wordsWritten, 3)
        c.processReading(count: 8)      // wrote 3 more
        XCTAssertEqual(c.wordsWritten, 6)
    }

    func testProcessReading_smallBackspaceIgnored() {
        var c = FocusWordCounter()
        c.baseline(count: 0)
        c.processReading(count: 10)     // +10
        c.processReading(count: 8)      // -2 (backspace), within threshold → ignored
        XCTAssertEqual(c.wordsWritten, 10)
        c.processReading(count: 12)     // +4 from new lastCount(8)
        XCTAssertEqual(c.wordsWritten, 14)
    }

    func testProcessReading_largeDropRebasesWithoutSubtracting() {
        var c = FocusWordCounter()
        c.baseline(count: 0)
        c.processReading(count: 20)     // +20
        c.processReading(count: 3)      // -17 (> threshold 5) → field switch, rebase
        XCTAssertEqual(c.wordsWritten, 20)
        c.processReading(count: 6)      // +3 from new lastCount(3)
        XCTAssertEqual(c.wordsWritten, 23)
    }

    func testResumeCounting_keepsWordsRebasesLast() {
        var c = FocusWordCounter()
        c.baseline(count: 0)
        c.processReading(count: 10)     // 10 words written
        c.rebaseline(count: 100)        // resumed in a different/longer field
        c.processReading(count: 102)    // +2 only
        XCTAssertEqual(c.wordsWritten, 12)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FocusWordCountTests`
Expected: FAIL — `FocusWordCounter` not found / no such members.

- [ ] **Step 3: Write minimal implementation**

Create `Core/FocusWordCounter.swift`:

```swift
import Foundation

/// Counts words the user types during a focus session by diffing the focused
/// field's word count over time. Positive deltas accumulate; small negative
/// deltas (backspace) are ignored; large drops (field/app switch) rebase the
/// baseline without subtracting.
///
/// The delta logic (`processReading`/`baseline`/`rebaseline`) is pure and
/// synchronous so it unit-tests without Accessibility. The AX poll loop lives
/// in `start()`/`stop()` and feeds readings into `processReading`.
@MainActor
final class FocusWordCounter: ObservableObject {

    /// Word-count drop larger than this (in words) is treated as a field switch.
    static let rebaseThreshold = 5

    @Published private(set) var wordsWritten: Int = 0
    private var lastCount: Int = 0

    private var pollTask: Task<Void, Never>?

    // MARK: - Pure core (testable)

    static func wordCount(_ s: String) -> Int {
        s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Reset accumulated words and set the starting baseline.
    func baseline(count: Int) {
        wordsWritten = 0
        lastCount = count
    }

    /// Move the baseline to `count` without changing accumulated words.
    func rebaseline(count: Int) {
        lastCount = count
    }

    /// Feed a fresh word-count reading and update `wordsWritten`.
    func processReading(count: Int) {
        let delta = count - lastCount
        if delta > 0 {
            wordsWritten += delta
        }
        // delta <= 0: backspace (small) or field switch (large) — either way
        // we only rebase lastCount, never subtract.
        lastCount = count
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FocusWordCountTests`
Expected: PASS (all 6).

- [ ] **Step 5: Commit**

```bash
git add Core/FocusWordCounter.swift Tests/FocusModeTests.swift
git commit -m "feat(focus): word-count + delta pure cores with tests"
```

---

## Task 2: AX poll loop + bridge read

Wire the counter to Accessibility so it reads the live focused field.

**Files:**
- Modify: `Accessibility/AccessibilityBridge.swift`
- Modify: `Core/FocusWordCounter.swift`

- [ ] **Step 1: Add the bridge read method**

In `Accessibility/AccessibilityBridge.swift`, add this method inside the `actor AccessibilityBridge` body (place it right after `fetchSelectedText(fromPID:)`, near line 152):

```swift
    /// Full plain text of the focused element of `pid` (its kAXValueAttribute),
    /// or nil if unavailable. Used by Focus Mode's word counter — does not throw,
    /// does not prefer selected text.
    func focusedPlainText(pid: pid_t) async -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let appAX = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                appAX, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef,
              let element = Self.asElement(focused) else { return nil }
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                element, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String else { return nil }
        return value
    }
```

- [ ] **Step 2: Add the poll loop to FocusWordCounter**

In `Core/FocusWordCounter.swift`, add the lifecycle methods to the class (after `processReading`):

```swift
    // MARK: - AX poll lifecycle

    /// Reset, take an initial baseline from the focused field, and start polling.
    func start() {
        pollTask?.cancel()
        wordsWritten = 0
        Task { [weak self] in
            await self?.takeBaseline()
            self?.runPoll(rebaseOnFirstRead: false)
        }
    }

    /// Re-arm polling after a pause without zeroing accumulated words.
    /// Re-baselines to the current field on the next read.
    func resumeCounting() {
        pollTask?.cancel()
        Task { [weak self] in
            await self?.takeBaseline()        // rebaseline only; wordsWritten preserved
            self?.runPoll(rebaseOnFirstRead: false)
        }
    }

    /// Stop polling. `wordsWritten` keeps its final value.
    func pause() { pollTask?.cancel(); pollTask = nil }
    func stop()  { pollTask?.cancel(); pollTask = nil }

    private func takeBaseline() async {
        let pid = await AccessibilityBridge.shared.lastKnownFrontAppPID()
        let text = await AccessibilityBridge.shared.focusedPlainText(pid: pid)
        lastCount = text.map { Self.wordCount($0) } ?? lastCount
    }

    private func runPoll(rebaseOnFirstRead: Bool) {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                let pid = await AccessibilityBridge.shared.lastKnownFrontAppPID()
                guard let text = await AccessibilityBridge.shared.focusedPlainText(pid: pid)
                else { continue }   // read failed — leave state unchanged
                self.processReading(count: Self.wordCount(text))
            }
        }
    }
```

Note: `baseline(count:)` from Task 1 is still used by tests; `takeBaseline()` sets
`lastCount` directly to avoid zeroing `wordsWritten` on resume. Keep both.

- [ ] **Step 3: Verify build**

Run: `swift build`
Expected: `Build complete!` with no errors. (Warnings about unhandled resource files are pre-existing and OK.)

- [ ] **Step 4: Re-run Task 1 tests (no regression)**

Run: `swift test --filter FocusWordCountTests`
Expected: PASS (all 6 still green — pure core unchanged).

- [ ] **Step 5: Commit**

```bash
git add Core/FocusWordCounter.swift Accessibility/AccessibilityBridge.swift
git commit -m "feat(focus): AX poll loop + focusedPlainText bridge read"
```

---

## Task 3: Fix FocusTimer (resume + counter + endEarly)

Fix the resume duration bug, integrate the word counter, stop celebrating in `finish()`, add `endEarly()`.

**Files:**
- Modify: `Core/FocusTimer.swift`
- Test: `Tests/FocusModeTests.swift`

- [ ] **Step 1: Write the failing test for resume-time math**

Append to `Tests/FocusModeTests.swift`:

```swift
@MainActor
final class FocusTimerMathTests: XCTestCase {
    func testResumeStart_preservesElapsed() {
        // Paused after 40s of a 60s session: 20s remain.
        // Resuming "now" must place startTime 40s in the past so the
        // countdown continues from 20s, not restart at 60s.
        let now = Date(timeIntervalSince1970: 1_000_000)
        let start = FocusTimer.resumeStartTime(elapsed: 40, now: now)
        let durationSeconds = 60
        let remaining = max(0, durationSeconds - Int(now.timeIntervalSince(start)))
        XCTAssertEqual(remaining, 20)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FocusTimerMathTests`
Expected: FAIL — `resumeStartTime` not found.

- [ ] **Step 3: Rewrite FocusTimer**

Replace the entire contents of `Core/FocusTimer.swift` with:

```swift
import Foundation
import Combine
import OSLog

/// Single-session countdown timer for Focus Mode.
///
/// Fires a 1 Hz tick via Task.sleep. Reports elapsed/remaining time, owns the
/// word counter, and updates FocusMode.state on completion so the rest of the
/// app observes the transition. On finish it surfaces the recap panel; it does
/// NOT record stats or celebrate — that happens after the user confirms in the
/// recap (see FocusSessionView).
@MainActor
final class FocusTimer: ObservableObject {
    static let shared = FocusTimer()

    enum TimerState: Equatable {
        case idle
        case running(durationSeconds: Int, startTime: Date)
        case paused(elapsed: Int, remaining: Int)
        case finished
    }

    @Published var timerState: TimerState = .idle
    @Published var elapsedSeconds: Int = 0

    let wordCounter = FocusWordCounter()

    var wordsWritten: Int { wordCounter.wordsWritten }

    var remainingSeconds: Int {
        switch timerState {
        case .running(let dur, let start):
            return max(0, dur - Int(Date().timeIntervalSince(start)))
        case .paused(_, let rem):
            return rem
        default:
            return 0
        }
    }

    var isActive: Bool { if case .running = timerState { return true }; return false }
    var isPaused: Bool { if case .paused = timerState { return true }; return false }

    private var task: Task<Void, Never>?

    private init() {}

    /// Pure helper: where to place startTime when resuming so `elapsed`
    /// seconds are preserved. Testable without real time.
    static func resumeStartTime(elapsed: Int, now: Date) -> Date {
        now.addingTimeInterval(-Double(elapsed))
    }

    func start(durationMinutes: Int) {
        task?.cancel()
        let secs = durationMinutes * 60
        timerState = .running(durationSeconds: secs, startTime: .now)
        elapsedSeconds = 0
        FocusMode.shared.startSession(durationMinutes: durationMinutes)
        wordCounter.start()
        runTick()
    }

    func pause() {
        guard case .running(let dur, let start) = timerState else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        timerState = .paused(elapsed: elapsed, remaining: max(0, dur - elapsed))
        task?.cancel()
        wordCounter.pause()
    }

    func resume() {
        guard case .paused(let elapsed, let remaining) = timerState else { return }
        let dur = elapsed + remaining
        timerState = .running(durationSeconds: dur,
                              startTime: Self.resumeStartTime(elapsed: elapsed, now: .now))
        wordCounter.resumeCounting()
        runTick()
    }

    func stop() {
        task?.cancel()
        timerState = .idle
        elapsedSeconds = 0
        wordCounter.stop()
        FocusMode.shared.endSession()
    }

    /// User ended before the timer expired. If they wrote something and spent
    /// at least a minute, surface the recap so the session can be recorded;
    /// otherwise just reset.
    func endEarly() {
        let elapsed = elapsedSeconds
        task?.cancel()
        wordCounter.stop()
        FocusMode.shared.endSession()
        if wordsWritten > 0 && elapsed >= 60 {
            elapsedSeconds = elapsed
            timerState = .finished
            FocusSessionPanel.shared.show()
        } else {
            timerState = .idle
            elapsedSeconds = 0
        }
    }

    private func runTick() {
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    private func tick() {
        guard case .running(let dur, let start) = timerState else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        if elapsed >= dur { finish(); return }
        elapsedSeconds = elapsed
        objectWillChange.send()
    }

    private func finish() {
        guard case .running(let dur, _) = timerState else { return }
        task?.cancel()
        wordCounter.stop()
        elapsedSeconds = dur
        timerState = .finished
        FocusMode.shared.endSession()
        objectWillChange.send()
        FocusSessionPanel.shared.show()   // surface recap; record/celebrate happen there
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FocusTimerMathTests`
Expected: PASS.

- [ ] **Step 5: Verify build**

Run: `swift build`
Expected: `Build complete!` (FocusSessionPanel.shared resolves after Task 5 — if this task is implemented before Task 5, the build will fail on `FocusSessionPanel.shared`. Implement Task 5 in the same batch, or temporarily comment the two `FocusSessionPanel.shared.show()` lines and restore them in Task 5. Prefer batching Tasks 3+5.)

- [ ] **Step 6: Commit**

```bash
git add Core/FocusTimer.swift Tests/FocusModeTests.swift
git commit -m "fix(focus): resume preserves remaining; integrate word counter; recap on finish"
```

---

## Task 4: FocusStatsStore — pure streak + freeze preference

Extract streak computation to a pure function and respect the configurable freeze.

**Files:**
- Modify: `Core/FocusStatsStore.swift`
- Test: `Tests/FocusModeTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/FocusModeTests.swift`:

```swift
@MainActor
final class FocusStreakTests: XCTestCase {
    private func key(_ daysAgo: Int, from today: Date) -> String {
        let cal = Calendar.current
        let date = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: today))!
        let df = DateFormatter(); df.calendar = cal
        df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }

    func testStreak_consecutiveDays() {
        let today = Date()
        let keys: Set<String> = [key(0, from: today), key(1, from: today), key(2, from: today)]
        XCTAssertEqual(FocusStatsStore.computeStreak(loggedKeys: keys, today: today, freezeLimit: 0), 3)
    }

    func testStreak_gapBreaksWithoutFreeze() {
        let today = Date()
        let keys: Set<String> = [key(0, from: today), key(2, from: today)]  // missing day 1
        XCTAssertEqual(FocusStatsStore.computeStreak(loggedKeys: keys, today: today, freezeLimit: 0), 1)
    }

    func testStreak_oneFreezeBridgesOneGap() {
        let today = Date()
        let keys: Set<String> = [key(0, from: today), key(2, from: today), key(3, from: today)]
        // day1 missing, bridged by 1 freeze → 0,(1 freeze),2,3 = streak 3
        XCTAssertEqual(FocusStatsStore.computeStreak(loggedKeys: keys, today: today, freezeLimit: 1), 3)
    }

    func testStreak_emptyIsZero() {
        XCTAssertEqual(FocusStatsStore.computeStreak(loggedKeys: [], today: Date(), freezeLimit: 1), 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FocusStreakTests`
Expected: FAIL — `computeStreak` not found.

- [ ] **Step 3: Extract the pure function and wire the preference**

In `Core/FocusStatsStore.swift`, add this static method to the class (place it just above the `recomputeStreak()` method):

```swift
    /// Pure streak computation: count consecutive days ending today that have a
    /// logged entry, allowing up to `freezeLimit` missing days to be skipped.
    /// `loggedKeys` are "yyyy-MM-dd" (POSIX) keys.
    static func computeStreak(loggedKeys: Set<String>, today: Date, freezeLimit: Int) -> Int {
        let cal = Calendar.current
        let df = DateFormatter()
        df.calendar = cal
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"

        var streak = 0
        var date = cal.startOfDay(for: today)
        var freezesUsed = 0

        while streak < 365 {
            let k = df.string(from: date)
            if loggedKeys.contains(k) {
                streak += 1
            } else if freezesUsed < freezeLimit {
                freezesUsed += 1
            } else {
                break
            }
            date = cal.date(byAdding: .day, value: -1, to: date)!
        }
        return streak
    }
```

Then replace the body of the existing private `recomputeStreak()` with a call to it:

```swift
    private func recomputeStreak() {
        let freeze = min(7, max(0, PreferencesStore.shared.focusStreakFreeze))
        let streak = Self.computeStreak(loggedKeys: Set(dailyLog.keys), today: .now, freezeLimit: freeze)
        currentStreak = streak
        if streak > longestStreak { longestStreak = streak }
    }
```

Also remove the now-unused `private let streakFreezeLimit = 1` line.

Make `dateKey(_:)` use a POSIX locale so keys match `computeStreak`. Replace the
existing `dateKey` body with:

```swift
    private func dateKey(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FocusStreakTests`
Expected: PASS (all 4).

- [ ] **Step 5: Verify build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add Core/FocusStatsStore.swift Tests/FocusModeTests.swift
git commit -m "fix(focus): pure computeStreak + configurable streak freeze"
```

---

## Task 5: Recap/record flow + FocusSessionPanel singleton

Single correct flow: record real words, then celebrate. Panel becomes a singleton so the recap is always reachable.

**Files:**
- Modify: `UI/FocusTab.swift`
- Modify: `UI/FocusSessionView.swift`
- Modify: `UI/MenuBarView.swift`

- [ ] **Step 1: Make FocusSessionPanel a singleton**

In `UI/FocusTab.swift`, change the `FocusSessionPanel` class declaration. Replace:

```swift
@MainActor
final class FocusSessionPanel {
    private var window: NSWindow?
```

with:

```swift
@MainActor
final class FocusSessionPanel {
    static let shared = FocusSessionPanel()
    private init() {}
    private var window: NSWindow?
```

- [ ] **Step 2: Point MenuBarView at the singleton**

In `UI/MenuBarView.swift`, find the "Start session" button action:

```swift
            Button {
                let panel = FocusSessionPanel()
                panel.show()
            } label: {
```

Replace the two body lines with:

```swift
            Button {
                FocusSessionPanel.shared.show()
            } label: {
```

- [ ] **Step 3: Fix the recap record/celebrate flow**

In `UI/FocusSessionView.swift`, replace the entire `recapView` computed property with:

```swift
    private var recapView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text("Session complete!")
                .font(.title2.weight(.bold))

            HStack(spacing: 24) {
                statItem(value: "\(timer.elapsedSeconds / 60)", label: "minutes")
                statItem(value: "\(timer.wordsWritten)", label: "words")
                if stats.currentStreak > 0 {
                    statItem(value: "\(stats.currentStreak)", label: "day streak")
                }
            }

            Button("Record & continue") {
                let words = timer.wordsWritten
                let minutes = timer.elapsedSeconds / 60
                stats.recordSession(words: words, minutes: minutes, mood: selectedMood)
                FocusCelebration.shared.celebrateSessionComplete(words: words, minutes: minutes)
                timer.stop()
                FocusOverlayWindow.shared.hide()
                FocusSessionPanel.shared.close()
            }
            .buttonStyle(.borderedProminent)

            Button("Discard") {
                timer.stop()
                FocusOverlayWindow.shared.hide()
                FocusSessionPanel.shared.close()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
```

Also update `activeSessionView` so ending early routes through `endEarly()`. Replace its `Button` action body:

```swift
            Button {
                timer.stop()
                FocusOverlayWindow.shared.hide()
            } label: {
```

with:

```swift
            Button {
                timer.endEarly()
                FocusOverlayWindow.shared.hide()
            } label: {
```

- [ ] **Step 4: Verify build**

Run: `swift build`
Expected: `Build complete!` (Tasks 3, 4, 5 together now compile — `FocusSessionPanel.shared`, `timer.wordsWritten`, `timer.endEarly()` all resolve.)

- [ ] **Step 5: Commit**

```bash
git add UI/FocusTab.swift UI/FocusSessionView.swift UI/MenuBarView.swift
git commit -m "fix(focus): singleton session panel + correct record/celebrate flow"
```

---

## Task 6: Overlay pause/resume + stop + auto-hide

Make the floating overlay's controls actually drive the timer.

**Files:**
- Modify: `UI/FocusOverlayWindow.swift`

- [ ] **Step 1: Fix the overlay controls**

In `UI/FocusOverlayWindow.swift`, inside `FocusOverlayContent`, replace the `// Controls` `VStack` (the pause and X buttons) with:

```swift
            // Controls
            VStack(spacing: 4) {
                Button {
                    if timer.isPaused { timer.resume() } else { timer.pause() }
                } label: {
                    Image(systemName: timer.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 12))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(timer.isPaused ? "Resume session" : "Pause session")

                Button {
                    timer.endEarly()
                    FocusOverlayWindow.shared.hide()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Stop session")
            }
```

- [ ] **Step 2: Auto-hide overlay when the session ends**

Still in `FocusOverlayContent`, add an `.onChange` to the root `HStack` (attach it after the existing `.frame(width: 280, height: 70)` modifier):

```swift
        .onChange(of: timer.timerState) { _, newState in
            switch newState {
            case .finished, .idle:
                FocusOverlayWindow.shared.hide()
            default:
                break
            }
        }
```

- [ ] **Step 3: Verify build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add UI/FocusOverlayWindow.swift
git commit -m "fix(focus): overlay pause/resume toggle, X stops timer, auto-hide on end"
```

---

## Task 7: Honest P2 settings

Stop the UI from claiming unimplemented features.

**Files:**
- Modify: `UI/FocusTab.swift`

- [ ] **Step 1: Disable the unimplemented controls**

In `UI/FocusTab.swift`, replace the "Options" `Section` and the "Background sound" picker so the not-yet-built controls are disabled and labeled. Replace the `Picker("Background sound", …)` block with:

```swift
                    Picker("Background sound (coming soon)", selection: $prefs.focusSound) {
                        Text("Silence").tag("silence")
                        Text("Coffee shop").tag("coffee")
                        Text("Rain").tag("rain")
                        Text("Lo-fi").tag("lofi")
                    }
                    .disabled(true)
```

And replace the three P2 toggles in the "Options" section:

```swift
                    Toggle("Forward-only (no backspace)", isOn: $prefs.focusForwardOnly)
                    Toggle("Blindwrite (text fades as you type)", isOn: $prefs.focusBlindwrite)
                    Toggle("Kiosk mode (no escape)", isOn: $prefs.focusKiosk)
```

with:

```swift
                    Toggle("Forward-only (no backspace) — coming soon", isOn: $prefs.focusForwardOnly)
                        .disabled(true)
                    Toggle("Blindwrite (text fades as you type) — coming soon", isOn: $prefs.focusBlindwrite)
                        .disabled(true)
                    Toggle("Kiosk mode (no escape) — coming soon", isOn: $prefs.focusKiosk)
                        .disabled(true)
```

(The `Stepper` for streak freeze stays enabled — it is now wired in Task 4.)

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add UI/FocusTab.swift
git commit -m "chore(focus): mark unimplemented P2 options as coming soon"
```

---

## Task 8: Full verification

- [ ] **Step 1: Run the whole test suite**

Run: `swift test`
Expected: all tests pass, including the new `FocusWordCountTests`, `FocusTimerMathTests`, `FocusStreakTests`. No failures.

- [ ] **Step 2: Build the app product**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Manual smoke test (record results)**

Launch the app (use the project's existing run path, e.g. `core/build-wren.sh`, then grant Accessibility if prompted). Verify:
- Start a 5-min session from the menu bar → overlay appears.
- Type a paragraph in TextEdit → overlay "words today" climbs within ~2s ticks.
- Confirm completion ghost text and corrections do NOT appear during the session.
- Pause via overlay → countdown freezes; resume → continues from where it paused (NOT restarted), words keep counting.
- Let the timer finish (or end early after >1 min with words) → recap panel shows the real word count.
- "Record & continue" → toast appears; DashboardTab "Words in focus" + week heatmap update; streak = 1 day.
- After the session, completion + correction work again.

- [ ] **Step 4: Final commit (if any manual-fix tweaks were needed)**

```bash
git add -A
git commit -m "test(focus): manual smoke verification fixes"
```

(Skip if no changes.)

---

## Notes for the implementer

- Run every command from `core/` (the submodule directory), not the outer `Wren` repo.
- Pre-existing build warnings about unhandled resource files and invalid excludes are
  unrelated to this work — ignore them.
- Tasks 3 and 5 are interdependent (`FocusSessionPanel.shared` and `timer.endEarly()` /
  `timer.wordsWritten`). Implement and build them together; do not expect a green build
  after Task 3 alone.
- The outer `Wren` repo's `core` submodule pointer will move when you commit inside
  `core`. Per the user's instruction, do NOT commit the submodule-pointer bump in the
  outer repo yet — that happens at the end once everything works.
