# Wren Onboarding & Tone Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Wren a mode-gated, Wren-native first-run flow that requests the right permission, captures the user's writing tone (optional, case-spanning phrases + paste + upload), downloads the model in the background, and keeps improving via an optional recurring tune-up.

**Architecture:** Separate `WrenOnboardingView` + shared `OnboardingScaffold`, with the current Parrot flow renamed to `ParrotOnboardingView`. A view-level `@Observable ModelDownloadCoordinator` runs the background download. Tone capture is a reusable `TonePracticeView` driven by pure `ToneSeeder` logic that feeds the existing `CorpusLearner` / `CompletionLearningStore` / `StyleProfile` pipeline. A pure `ToneTuneUpScheduler` decides when to resurface practice.

**Tech Stack:** Swift / SwiftUI, macOS AppKit (`NSWindow`, `IOKit.hid`), Swift Concurrency (actors, `AsyncThrowingStream`), XCTest. Module under test: `Parrot`. Tests live in `Tests/`, run with `swift test`.

---

## Conventions (read once)

- **Repo root for all paths below:** the core submodule `~/Desktop/Progetti dev/Swift/Wren/core/`.
- **Build:** `swift build` (needs llama dylibs at `/opt/homebrew/lib`; if `.build` has a stale absolute path, `rm -rf .build && swift package resolve` first).
- **Test:** `swift test --filter <TestClass>` (e.g. `swift test --filter ToneSeederTests`).
- **Test import:** `@testable import Parrot`.
- **New test files:** `Tests/OnboardingTests/`.
- **Branch:** already on `feat/wren-onboarding`. Commit after every task.
- **PreferencesStore pattern** (for new settings): a computed var backed by `Constants.UserDefaultsKey`, e.g.
  `var x: Bool { get { bool(Constants.UserDefaultsKey.x) } set { set(newValue, for: Constants.UserDefaultsKey.x) } }`.

---

## File Structure

**New files:**
- `Core/Completion/ToneSeeder.swift` — pure: turns onboarding input (phrase completions / pasted text) into seeded entries + a learned-count, and records style samples. No UI.
- `Core/Completion/TonePhrases.swift` — pure: the curated, localized, case-spanning phrase set + rotation logic.
- `Core/Completion/ToneTuneUpScheduler.swift` — pure: given last-run date + cadence + now, decides if a tune-up is due. Injectable clock.
- `UI/OnboardingScaffold.swift` — shared chrome (footer bar, step dots, container) extracted from the current `OnboardingView`.
- `UI/Onboarding/WrenOnboardingView.swift` — Wren root flow + its step subviews.
- `UI/Onboarding/ModelDownloadCoordinator.swift` — `@Observable` background-download state.
- `UI/TonePracticeView.swift` — reusable tone-capture UI (phrases + paste + upload), used by onboarding step 2 and the recurring tune-up.

**Modified files:**
- `UI/OnboardingView.swift` — rename `OnboardingView` → `ParrotOnboardingView`; make `OnboardingController` mode-gated; per-mode completion key.
- `App/AppDelegate.swift` — AppMode-aware status-item label/help (B1); wire the tune-up scheduler.
- `Core/Completion/CompletionLearningStore.swift` — add `recordStyleSample(from:)` so onboarding text updates `StyleProfile`.
- `Core/Completion/LlamaCompletionClient.swift` — thread `styleDescriptor` into the chat prompt (C2).
- `Infra/PreferencesStore.swift` + `App/Constants.swift` — add `toneTuneUpCadence` setting + key.
- `UI/CompletionTab.swift` — cadence picker UI.

---

## Task 1: AppMode-aware branding (B1 + window title)

**Files:**
- Modify: `App/AppDelegate.swift:140-142` (status item label/help)
- Modify: `UI/OnboardingView.swift:30` (window title)

This task has no unit test (AppKit label strings); verify by reading. It is a safe, isolated first commit.

- [ ] **Step 1: Replace hardcoded "Parrot" in the status item**

In `App/AppDelegate.swift`, inside `setupStatusItem()`, replace:

```swift
        button.setAccessibilityLabel("Parrot menu")
        button.setAccessibilityHelp("Open the Parrot correction menu")
```

with:

```swift
        let appName = AppMode.current.displayName
        button.setAccessibilityLabel("\(appName) menu")
        button.setAccessibilityHelp(AppMode.current.showsCompletion
            ? "Open the \(appName) completion menu"
            : "Open the \(appName) correction menu")
```

- [ ] **Step 2: Make the onboarding window title mode-aware**

In `UI/OnboardingView.swift`, in `OnboardingController.show()`, replace:

```swift
        w.title = "Initial Setup — Parrot"
```

with:

```swift
        w.title = "Initial Setup — \(AppMode.current.displayName)"
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds with no new errors.

- [ ] **Step 4: Commit**

```bash
git add App/AppDelegate.swift UI/OnboardingView.swift
git commit -m "fix(wren): AppMode-aware status item label + onboarding title (B1/B2)"
```

---

## Task 2: Mode-gate onboarding + rename Parrot view

**Files:**
- Modify: `UI/OnboardingView.swift` (rename type, add gating, per-mode key)
- Create: `UI/Onboarding/WrenOnboardingView.swift` (temporary stub, replaced in Task 13)
- Test: `Tests/OnboardingTests/OnboardingControllerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/OnboardingTests/OnboardingControllerTests.swift`:

```swift
import XCTest
@testable import Parrot

final class OnboardingControllerTests: XCTestCase {
    func test_completionKey_isPerMode() {
        // Parrot and Wren must use distinct completion flags so an existing
        // Parrot user still sees the Wren onboarding.
        XCTAssertNotEqual(
            OnboardingController.completionKey(for: .parrot),
            OnboardingController.completionKey(for: .wren)
        )
        XCTAssertEqual(OnboardingController.completionKey(for: .wren),
                       "hasCompletedOnboarding_wren_v1")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter OnboardingControllerTests`
Expected: FAIL — `completionKey(for:)` does not exist.

- [ ] **Step 3: Rename the Parrot view and add gating**

In `UI/OnboardingView.swift`:

1. Rename `struct OnboardingView` → `struct ParrotOnboardingView` (and the `#Preview` at the bottom: `ParrotOnboardingView(onComplete: {})`).
2. Replace the `OnboardingController` body with mode-gating:

```swift
@MainActor
final class OnboardingController {
    static let shared = OnboardingController()

    private var window: NSWindow?

    static func completionKey(for mode: AppMode) -> String {
        mode == .wren ? "hasCompletedOnboarding_wren_v1" : "hasCompletedOnboarding_v2"
    }

    func showIfNeeded() {
        let key = Self.completionKey(for: .current)
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        show()
    }

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Initial Setup — \(AppMode.current.displayName)"
        w.center()
        w.isReleasedWhenClosed = false
        w.setFrameAutosaveName("OnboardingWindow")

        let onComplete: () -> Void = { [weak self] in
            UserDefaults.standard.set(true, forKey: Self.completionKey(for: .current))
            self?.window?.close()
            self?.window = nil
        }
        let root: AnyView = AppMode.current.showsCompletion
            ? AnyView(WrenOnboardingView(onComplete: onComplete))
            : AnyView(ParrotOnboardingView(onComplete: onComplete))
        w.contentView = NSHostingView(rootView: root)

        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

Note: `AppMode.current` is a `let` resolved from the bundle id; `.current` is used directly (the `for: .current` form passes the resolved mode). The `completedKey` static constant is removed (replaced by `completionKey(for:)`).

- [ ] **Step 4: Add a stub Wren view so it compiles**

Create `UI/Onboarding/WrenOnboardingView.swift`:

```swift
import SwiftUI

/// Wren's first-run flow. Replaced with the full multi-step flow in later tasks.
struct WrenOnboardingView: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome to Wren").font(.largeTitle.bold())
            Button("Start using Wren") { onComplete() }
                .buttonStyle(.borderedProminent)
        }
        .frame(width: 620, height: 520)
        .background(Color.surfaceBackground)
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter OnboardingControllerTests`
Expected: PASS.

- [ ] **Step 6: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 7: Commit**

```bash
git add UI/OnboardingView.swift UI/Onboarding/WrenOnboardingView.swift Tests/OnboardingTests/OnboardingControllerTests.swift
git commit -m "feat(wren): mode-gate onboarding, rename Parrot view, per-mode key (O1)"
```

---

## Task 3: Extract OnboardingScaffold (shared chrome)

**Files:**
- Create: `UI/OnboardingScaffold.swift`
- Modify: `UI/OnboardingView.swift` (Parrot view uses the scaffold)

No new unit test (pure layout). Verify by build + that Parrot onboarding still renders its 8 steps.

- [ ] **Step 1: Create the scaffold**

Create `UI/OnboardingScaffold.swift`. It owns the footer bar, the step dots, Back/Next/Skip, and an optional footer accessory (used later for the Wren download bar):

```swift
import SwiftUI

/// Shared onboarding chrome: a content area above a footer with step dots and
/// Back / Skip / Next (or a final action). Parrot and Wren flows compose this so
/// neither re-implements navigation. `footerAccessory` lets a flow (Wren) show a
/// persistent download bar above the buttons.
struct OnboardingScaffold<Content: View, Accessory: View>: View {
    let step: Int
    let totalSteps: Int
    let finalActionTitle: String
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void
    let onFinish: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footerAccessory: () -> Accessory

    var body: some View {
        VStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.2), value: step)

            Divider()
            footerAccessory()
            footerBar
        }
        .frame(width: 620, height: 520)
        .background(Color.surfaceBackground)
    }

    private var footerBar: some View {
        HStack(spacing: 16) {
            if step > 0 {
                Button("Back", action: onBack)
                    .buttonStyle(.bordered).controlSize(.regular)
            }
            Spacer()
            dots
            Spacer()
            Button("Skip", action: onSkip)
                .buttonStyle(.plain)
                .foregroundStyle(Color.textSecondary)
                .font(.callout)
            if step < totalSteps - 1 {
                Button("Next", action: onNext)
                    .buttonStyle(.borderedProminent).controlSize(.regular)
                    .keyboardShortcut(.return, modifiers: [])
            } else {
                Button(finalActionTitle, action: onFinish)
                    .buttonStyle(.borderedProminent).controlSize(.regular)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Circle()
                    .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: i == step ? 8 : 6, height: i == step ? 8 : 6)
                    .animation(.spring(response: 0.3), value: step)
            }
        }
    }
}

extension OnboardingScaffold where Accessory == EmptyView {
    init(step: Int, totalSteps: Int, finalActionTitle: String,
         onBack: @escaping () -> Void, onNext: @escaping () -> Void,
         onSkip: @escaping () -> Void, onFinish: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(step: step, totalSteps: totalSteps, finalActionTitle: finalActionTitle,
                  onBack: onBack, onNext: onNext, onSkip: onSkip, onFinish: onFinish,
                  content: content, footerAccessory: { EmptyView() })
    }
}
```

- [ ] **Step 2: Make ParrotOnboardingView use the scaffold**

In `UI/OnboardingView.swift`, replace `ParrotOnboardingView`'s `body` + `bottomBar` + `stepDots` with a scaffold composition (keep `stepContent` and the `step`/`prefs`/`totalSteps` state as-is):

```swift
    var body: some View {
        OnboardingScaffold(
            step: step,
            totalSteps: totalSteps,
            finalActionTitle: "Start using Parrot",
            onBack: { step -= 1 },
            onNext: { step += 1 },
            onSkip: onComplete,
            onFinish: onComplete,
            content: { stepContent }
        )
    }
```

Delete the now-unused `private var bottomBar` and `private var stepDots` from `ParrotOnboardingView`.

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds clean. (Manually sanity-check later that Parrot's 8 steps still navigate.)

- [ ] **Step 4: Commit**

```bash
git add UI/OnboardingScaffold.swift UI/OnboardingView.swift
git commit -m "refactor(onboarding): extract shared OnboardingScaffold chrome"
```

---

## Task 4: CompletionLearningStore.recordStyleSample (StyleProfile from onboarding text)

`seed()` does NOT update `StyleProfile` (only `record()` does). Onboarding text must update the profile so `styleDescriptor()` becomes non-empty.

**Files:**
- Modify: `Core/Completion/CompletionLearningStore.swift`
- Test: `Tests/OnboardingTests/StyleSampleTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/OnboardingTests/StyleSampleTests.swift`:

```swift
import XCTest
@testable import Parrot

final class StyleSampleTests: XCTestCase {
    func test_recordStyleSample_populatesDescriptor() async {
        let store = CompletionLearningStore()
        // Three sentences so StyleProfile's >=3 gate is met.
        await store.recordStyleSample(from: "I don't think so. It's fine. We're good.")
        let d = await store.styleDescriptor()
        XCTAssertFalse(d.isEmpty, "descriptor should be non-empty after >=3 sentences")
    }

    func test_recordStyleSample_emptyText_isNoop() async {
        let store = CompletionLearningStore()
        await store.recordStyleSample(from: "   ")
        let d = await store.styleDescriptor()
        XCTAssertTrue(d.isEmpty)
    }
}
```

Note: `CompletionLearningStore()` is constructible (the `init` is implicit; `shared` is a separate singleton). If the type currently forbids non-singleton init, add an internal `init() {}`.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter StyleSampleTests`
Expected: FAIL — `recordStyleSample(from:)` does not exist.

- [ ] **Step 3: Implement**

In `Core/Completion/CompletionLearningStore.swift`, add inside the actor:

```swift
    /// Updates the writing-style fingerprint from a raw sample (e.g. onboarding phrase
    /// completions or pasted text). Unlike `seed`, this feeds `StyleProfile` so
    /// `styleDescriptor()` can populate. No-op for blank text.
    func recordStyleSample(from text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        loadIfNeeded()
        profile.update(from: text)
        save()
    }
```

If needed for the test, also add `init() {}` (internal) near the top of the actor.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter StyleSampleTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Core/Completion/CompletionLearningStore.swift Tests/OnboardingTests/StyleSampleTests.swift
git commit -m "feat(completion): recordStyleSample feeds StyleProfile from raw text"
```

---

## Task 5: ToneSeeder (pure tone-capture logic)

**Files:**
- Create: `Core/Completion/ToneSeeder.swift`
- Test: `Tests/OnboardingTests/ToneSeederTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/OnboardingTests/ToneSeederTests.swift`:

```swift
import XCTest
@testable import Parrot

final class ToneSeederTests: XCTestCase {
    func test_phraseCompletions_areJoinedAndLearned() async {
        let store = CompletionLearningStore()
        let result = await ToneSeeder.learn(
            phraseCompletions: [(opener: "Dear team, I am writing to",
                                 continuation: "follow up on yesterday's meeting and the next steps")],
            pastedText: nil,
            store: store
        )
        // CorpusLearner needs >=3 words per line and repeated keys (minCount 2);
        // a single short phrase may seed 0 entries — the contract is "no crash,
        // count >= 0, style recorded".
        XCTAssertGreaterThanOrEqual(result.seededCount, 0)
        let d = await store.styleDescriptor()
        XCTAssertFalse(d.isEmpty)  // the joined sentence updated the profile
    }

    func test_emptyInput_seedsNothing_andRecordsNothing() async {
        let store = CompletionLearningStore()
        let result = await ToneSeeder.learn(
            phraseCompletions: [(opener: "Hi", continuation: "   ")],
            pastedText: "   ",
            store: store
        )
        XCTAssertEqual(result.seededCount, 0)
        let d = await store.styleDescriptor()
        XCTAssertTrue(d.isEmpty)
    }

    func test_pastedText_isLearned() async {
        let store = CompletionLearningStore()
        let text = """
        ti scrivo per confermare la riunione
        ti scrivo per confermare la disponibilità
        ti scrivo per confermare il preventivo
        """
        let result = await ToneSeeder.learn(phraseCompletions: [], pastedText: text, store: store)
        XCTAssertGreaterThan(result.seededCount, 0)  // repeated "ti scrivo per" key seeds
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ToneSeederTests`
Expected: FAIL — `ToneSeeder` undefined.

- [ ] **Step 3: Implement**

Create `Core/Completion/ToneSeeder.swift`:

```swift
import Foundation

/// Turns onboarding tone input into personalization. Pure orchestration over the existing
/// `CorpusLearner` (extracts context→continuation pairs) and `CompletionLearningStore`
/// (`seed` for instant completions, `recordStyleSample` for the StyleProfile fingerprint).
enum ToneSeeder {
    struct Result: Sendable { let seededCount: Int }

    /// Learns from completed example phrases and/or pasted text.
    /// - phraseCompletions: (opener, continuation) pairs; joined into full sentences.
    /// - pastedText: free text (paste or document contents).
    static func learn(
        phraseCompletions: [(opener: String, continuation: String)],
        pastedText: String?,
        store: CompletionLearningStore = .shared
    ) async -> Result {
        var corpus = ""
        for p in phraseCompletions {
            let cont = p.continuation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cont.isEmpty else { continue }
            let opener = p.opener.trimmingCharacters(in: .whitespacesAndNewlines)
            let sentence = opener.isEmpty ? cont : opener + " " + cont
            corpus += sentence + "\n"
        }
        if let pasted = pastedText?.trimmingCharacters(in: .whitespacesAndNewlines), !pasted.isEmpty {
            corpus += pasted + "\n"
        }
        let trimmed = corpus.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Result(seededCount: 0) }

        let entries = CorpusLearner.extract(from: corpus)
        let seeded = await store.seed(entries)
        await store.recordStyleSample(from: corpus)
        return Result(seededCount: seeded)
    }

    /// Learns from files/folders (upload). Reuses CorpusLearner's file walker.
    static func learn(fromFiles urls: [URL], store: CompletionLearningStore = .shared) async -> Result {
        var corpus = ""
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let e = fm.enumerator(at: url, includingPropertiesForKeys: nil)
                while let f = e?.nextObject() as? URL {
                    if ["txt", "md", "markdown", "text"].contains(f.pathExtension.lowercased()),
                       let s = try? String(contentsOf: f, encoding: .utf8) { corpus += s + "\n" }
                }
            } else if let s = try? String(contentsOf: url, encoding: .utf8) {
                corpus += s + "\n"
            }
        }
        guard !corpus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return Result(seededCount: 0) }
        let entries = CorpusLearner.extract(from: corpus)
        let seeded = await store.seed(entries)
        await store.recordStyleSample(from: corpus)
        return Result(seededCount: seeded)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ToneSeederTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Core/Completion/ToneSeeder.swift Tests/OnboardingTests/ToneSeederTests.swift
git commit -m "feat(completion): ToneSeeder — onboarding input → seed + StyleProfile"
```

---

## Task 6: TonePhrases (curated, localized, case-spanning set)

Eugenio explicitly wants specific, hand-picked phrases covering distinct registers (overrides the no-hardcoded-lists preference for this set). Keep it as one small localized list, not branching logic.

**Files:**
- Create: `Core/Completion/TonePhrases.swift`
- Test: `Tests/OnboardingTests/TonePhrasesTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/OnboardingTests/TonePhrasesTests.swift`:

```swift
import XCTest
@testable import Parrot

final class TonePhrasesTests: XCTestCase {
    func test_allRegistersPresent_andNonEmpty() {
        let all = TonePhrases.all
        XCTAssertEqual(Set(all.map(\.register)), Set(TonePhrases.Register.allCases))
        XCTAssertTrue(all.allSatisfy { !$0.opener.isEmpty })
    }

    func test_rotation_isStableForSameSeed_andCoversOverTime() {
        let first = TonePhrases.rotating(count: 3, seed: 0)
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(first.map(\.opener), TonePhrases.rotating(count: 3, seed: 0).map(\.opener),
                       "same seed → same selection")
        // Different seeds should not always return the identical first phrase.
        let openers = (0..<TonePhrases.all.count).map { TonePhrases.rotating(count: 1, seed: $0).first!.opener }
        XCTAssertGreaterThan(Set(openers).count, 1, "rotation should cover different phrases")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TonePhrasesTests`
Expected: FAIL — `TonePhrases` undefined.

- [ ] **Step 3: Implement**

Create `Core/Completion/TonePhrases.swift`:

```swift
import Foundation

/// A small, curated set of sentence openers, one per writing register, used to capture the
/// user's tone. Openers are localized (`String(localized:)`) so the user completes them in
/// their own language. This is a deliberate fixed pedagogical set (per Eugenio), kept as a
/// single list — not per-app branching and not data-driven logic.
enum TonePhrases {
    enum Register: CaseIterable, Sendable { case formalEmail, casualMessage, workTechnical, narrative, politeRequest }

    struct Phrase: Sendable { let register: Register; let opener: String }

    static let all: [Phrase] = [
        Phrase(register: .formalEmail,
               opener: String(localized: "tone.opener.formalEmail", defaultValue: "Gentile Dottoressa, le scrivo per")),
        Phrase(register: .casualMessage,
               opener: String(localized: "tone.opener.casualMessage", defaultValue: "Ehi! Volevo solo dirti che")),
        Phrase(register: .workTechnical,
               opener: String(localized: "tone.opener.workTechnical", defaultValue: "Ho aggiornato il modulo e ora")),
        Phrase(register: .narrative,
               opener: String(localized: "tone.opener.narrative", defaultValue: "Quella mattina, appena sveglio,")),
        Phrase(register: .politeRequest,
               opener: String(localized: "tone.opener.politeRequest", defaultValue: "Ti andrebbe di")),
    ]

    /// Deterministic rotating subset of `count` phrases, offset by `seed` (e.g. a run counter),
    /// so each tune-up shows a fresh slice and covers more registers over time.
    static func rotating(count: Int, seed: Int) -> [Phrase] {
        guard !all.isEmpty, count > 0 else { return [] }
        let n = min(count, all.count)
        let start = ((seed % all.count) + all.count) % all.count
        return (0..<n).map { all[(start + $0) % all.count] }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TonePhrasesTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Core/Completion/TonePhrases.swift Tests/OnboardingTests/TonePhrasesTests.swift
git commit -m "feat(completion): curated case-spanning TonePhrases with rotation"
```

---

## Task 7: ModelDownloadCoordinator (background download state)

**Files:**
- Create: `UI/Onboarding/ModelDownloadCoordinator.swift`
- Test: `Tests/OnboardingTests/ModelDownloadCoordinatorTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/OnboardingTests/ModelDownloadCoordinatorTests.swift`:

```swift
import XCTest
@testable import Parrot

@MainActor
final class ModelDownloadCoordinatorTests: XCTestCase {
    func test_progressStream_movesToComplete() async {
        let coord = ModelDownloadCoordinator(streamProvider: { _, _ in
            AsyncThrowingStream { c in
                c.yield(.downloading(0.5)); c.yield(.verifying(0.9)); c.yield(.complete); c.finish()
            }
        }, onComplete: { _ in })
        await coord.start(modelID: "m", url: URL(string: "https://x/m.gguf")!, sha: nil)
        XCTAssertEqual(coord.phase, .complete)
        XCTAssertEqual(coord.progress, 1.0, accuracy: 0.001)
    }

    func test_error_setsErrorPhase() async {
        struct Boom: Error {}
        let coord = ModelDownloadCoordinator(streamProvider: { _, _ in
            AsyncThrowingStream { c in c.finish(throwing: Boom()) }
        }, onComplete: { _ in })
        await coord.start(modelID: "m", url: URL(string: "https://x/m.gguf")!, sha: nil)
        if case .failed = coord.phase {} else { XCTFail("expected .failed, got \(coord.phase)") }
    }

    func test_startWhenAlreadyComplete_isNoop() async {
        var calls = 0
        let coord = ModelDownloadCoordinator(streamProvider: { _, _ in
            calls += 1
            return AsyncThrowingStream { c in c.yield(.complete); c.finish() }
        }, onComplete: { _ in })
        await coord.start(modelID: "m", url: URL(string: "https://x/m.gguf")!, sha: nil)
        await coord.start(modelID: "m", url: URL(string: "https://x/m.gguf")!, sha: nil)
        XCTAssertEqual(calls, 1, "second start after complete must not re-download")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelDownloadCoordinatorTests`
Expected: FAIL — `ModelDownloadCoordinator` undefined.

- [ ] **Step 3: Implement**

Create `UI/Onboarding/ModelDownloadCoordinator.swift`:

```swift
import SwiftUI

/// Owns the Wren onboarding background model download so progress survives step changes.
/// Injectable `streamProvider` keeps it unit-testable without real network.
@MainActor
@Observable
final class ModelDownloadCoordinator {
    enum Phase: Equatable { case idle, downloading, verifying, complete, failed(String) }

    private(set) var phase: Phase = .idle
    private(set) var progress: Double = 0
    private(set) var statusMessage: String = ""

    typealias StreamProvider = (URL, String?) -> AsyncThrowingStream<DownloadProgress, Error>
    private let streamProvider: StreamProvider
    private let onComplete: (String) -> Void   // modelID
    private var task: Task<Void, Never>?

    init(streamProvider: @escaping StreamProvider = { url, sha in
            ModelManager.shared.downloadModelWithProgress(from: url, expectedSHA256: sha)
         },
         onComplete: @escaping (String) -> Void) {
        self.streamProvider = streamProvider
        self.onComplete = onComplete
    }

    var isFinished: Bool { phase == .complete }

    func start(modelID: String, url: URL, sha: String?) async {
        guard phase != .complete, phase != .downloading, phase != .verifying else { return }
        phase = .downloading
        progress = 0
        statusMessage = "Starting download…"
        do {
            for try await p in streamProvider(url, sha) {
                switch p {
                case .downloading(let f): phase = .downloading; progress = f; statusMessage = "Downloading \(Int(f * 100))%"
                case .verifying(let f): phase = .verifying; progress = f; statusMessage = "Verifying \(Int(f * 100))%"
                case .complete: phase = .complete; progress = 1.0; statusMessage = "Ready"
                }
            }
            if phase == .complete { onComplete(modelID) }
        } catch {
            phase = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ModelDownloadCoordinatorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add UI/Onboarding/ModelDownloadCoordinator.swift Tests/OnboardingTests/ModelDownloadCoordinatorTests.swift
git commit -m "feat(wren): ModelDownloadCoordinator background download state"
```

---

## Task 8: TonePracticeView (reusable tone-capture UI)

**Files:**
- Create: `UI/TonePracticeView.swift`

UI task — no fragile snapshot test; logic is already covered by `ToneSeederTests`/`TonePhrasesTests`. Verify by build.

- [ ] **Step 1: Implement the view**

Create `UI/TonePracticeView.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers

/// Reusable tone-capture UI: finish curated phrases (default) + optional paste + optional upload.
/// Used by Wren onboarding step 2 and by the recurring tune-up. Calls `ToneSeeder`; reports the
/// learned count via `onLearned`. Fully optional — the host provides Skip/Next.
struct TonePracticeView: View {
    let phrases: [TonePhrases.Phrase]
    var onLearned: (Int) -> Void = { _ in }

    @State private var continuations: [String]
    @State private var showPaste = false
    @State private var pasted = ""
    @State private var learnedCount: Int?
    @State private var isWorking = false

    init(phrases: [TonePhrases.Phrase], onLearned: @escaping (Int) -> Void = { _ in }) {
        self.phrases = phrases
        self.onLearned = onLearned
        _continuations = State(initialValue: Array(repeating: "", count: phrases.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Teach Wren your tone")
                .font(.title2.bold())
            Text("Finish a few sentences the way you'd actually write them. Optional — skip anytime.")
                .font(.callout).foregroundStyle(Color.textSecondary)

            ForEach(Array(phrases.enumerated()), id: \.offset) { idx, phrase in
                VStack(alignment: .leading, spacing: 4) {
                    Text(phrase.opener).font(.callout.weight(.medium))
                    TextField("…continue in your words", text: $continuations[idx], axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                }
            }

            DisclosureGroup("Or paste your own text", isExpanded: $showPaste) {
                TextEditor(text: $pasted)
                    .font(.body).frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.borderDefault.opacity(0.5)))
            }
            .font(.callout)

            HStack(spacing: 12) {
                Button("Upload a document…", action: pickFiles)
                    .buttonStyle(.bordered).controlSize(.small)
                Button(isWorking ? "Learning…" : "Learn my tone", action: learn)
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(isWorking)
                if let n = learnedCount {
                    Text(n > 0 ? "Learned \(n) patterns from your style"
                               : "I'll use this as a hint")
                        .font(.caption).foregroundStyle(Color.statusOk)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func learn() {
        isWorking = true
        let pairs = zip(phrases, continuations).map { (opener: $0.opener, continuation: $1) }
        let pasteText = showPaste ? pasted : nil
        Task {
            let r = await ToneSeeder.learn(phraseCompletions: pairs, pastedText: pasteText)
            await MainActor.run {
                learnedCount = r.seededCount
                isWorking = false
                onLearned(r.seededCount)
            }
        }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        isWorking = true
        Task {
            let r = await ToneSeeder.learn(fromFiles: urls)
            await MainActor.run {
                learnedCount = r.seededCount
                isWorking = false
                onLearned(r.seededCount)
            }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add UI/TonePracticeView.swift
git commit -m "feat(wren): reusable TonePracticeView (phrases + paste + upload)"
```

---

## Task 9: WrenOnboardingView — full flow assembly

**Files:**
- Modify: `UI/Onboarding/WrenOnboardingView.swift` (replace the Task 2 stub)

UI assembly — verify by build + manual run. Uses the scaffold, coordinator, and step subviews defined inline here.

- [ ] **Step 1: Replace the stub with the full flow**

Replace the contents of `UI/Onboarding/WrenOnboardingView.swift`:

```swift
import SwiftUI
import IOKit.hid

struct WrenOnboardingView: View {
    let onComplete: () -> Void

    @State private var step = 0
    @State private var coordinator: ModelDownloadCoordinator?
    @State private var recommended: ModelRecommendation?
    private let totalSteps = 5

    var body: some View {
        OnboardingScaffold(
            step: step,
            totalSteps: totalSteps,
            finalActionTitle: "Start using Wren",
            onBack: { step -= 1 },
            onNext: { step += 1 },
            onSkip: onComplete,
            onFinish: onComplete,
            content: { stepContent },
            footerAccessory: { downloadBar }
        )
        .task { await prepareDownload() }
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case 0: WrenWelcomeStep(recommended: recommended)
        case 1: InputMonitoringStep()
        case 2: TonePracticeView(phrases: TonePhrases.rotating(count: 3, seed: 0))
        case 3: WrenScreenContextStep()
        default: WrenReadyStep(coordinator: coordinator)
        }
    }

    @ViewBuilder private var downloadBar: some View {
        if let c = coordinator, c.phase != .complete {
            VStack(spacing: 2) {
                ProgressView(value: c.progress)
                Text(c.statusMessage).font(.caption2).foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 24).padding(.top, 8)
        }
    }

    private func prepareDownload() async {
        // Skip if a model is already installed.
        guard await ModelManager.shared.localModels().isEmpty else { return }
        let models = await ModelManager.shared.recommendedModels()
        guard let best = models.first else { return }
        recommended = best
        let coord = ModelDownloadCoordinator(onComplete: { id in
            PreferencesStore.shared.completionModelID = id
            PreferencesStore.shared.serviceType = .local
            Task.detached(priority: .utility) { await CompletionEngine.shared.warmup() }
        })
        coordinator = coord
        await coord.start(modelID: best.id, url: best.url, sha: best.expectedSHA256)
    }
}

// MARK: - Step 0: Welcome
private struct WrenWelcomeStep: View {
    let recommended: ModelRecommendation?
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "text.cursor")
                .font(.system(size: 56)).foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)
            Text("Welcome to Wren").font(.largeTitle.bold())
            Text("Wren predicts what you're about to type and shows it inline. Press Tab to accept.")
                .font(.title3).foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, 48)
            if let r = recommended {
                Text("Downloading \(r.name) in the background — \(r.reason)")
                    .font(.caption).foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }.padding()
    }
}

// MARK: - Step 1: Input Monitoring
private struct InputMonitoringStep: View {
    @State private var granted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: granted ? "checkmark.shield.fill" : "keyboard.badge.ellipsis")
                .font(.system(size: 44))
                .foregroundStyle(granted ? Color.statusOk : Color.statusWarning)
                .symbolRenderingMode(.hierarchical)
            Text(granted ? "Permission granted!" : "Input Monitoring")
                .font(.title2.bold())
            Text(granted
                 ? "Wren can see what you type so it can suggest completions."
                 : "Wren needs Input Monitoring to read your keystrokes and offer inline completions. Nothing leaves your Mac.")
                .multilineTextAlignment(.center).foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 48)
            if !granted {
                Button("Grant access") { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
                    .buttonStyle(.borderedProminent)
                Text("System Settings → Privacy & Security → Input Monitoring → enable Wren")
                    .font(.caption).foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
        .padding()
        .task {
            while !Task.isCancelled, !granted {
                try? await Task.sleep(for: .milliseconds(600))
                granted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
            }
        }
    }
}

// MARK: - Step 3: Screen Context (optional)
private struct WrenScreenContextStep: View {
    @State private var granted = ScreenContextProvider.hasPermission
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "rectangle.dashed.badge.record")
                .font(.system(size: 44)).foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)
            Text("Smarter suggestions (optional)").font(.title2.bold())
            Text("Let Wren read the conversation above your cursor to suggest more relevant completions. You can skip this and enable it later.")
                .multilineTextAlignment(.center).foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 48)
            if !granted {
                Button("Enable screen context") { ScreenContextProvider.requestPermission() }
                    .buttonStyle(.bordered)
            } else {
                Label("Enabled", systemImage: "checkmark.circle.fill").foregroundStyle(Color.statusOk)
            }
            Spacer()
        }.padding()
    }
}

// MARK: - Step 4: Ready
private struct WrenReadyStep: View {
    let coordinator: ModelDownloadCoordinator?
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48)).foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)
            Text("You're ready").font(.largeTitle.bold())
            if let c = coordinator, c.phase != .complete {
                if case .failed(let msg) = c.phase {
                    Text("Model download failed: \(msg). Retry from Settings → Models.")
                        .font(.caption).foregroundStyle(Color.statusError)
                        .multilineTextAlignment(.center).padding(.horizontal, 40)
                } else {
                    Text("Your model is still downloading — you can start now, it'll be ready in a moment.")
                        .font(.callout).foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 40)
                }
            } else {
                Text("Start typing anywhere and press Tab to accept Wren's suggestions.")
                    .font(.callout).foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }
            if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
                Text("⚠︎ Input Monitoring is off — enable it in System Settings for Wren to work.")
                    .font(.caption).foregroundStyle(Color.statusWarning)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }
            Spacer()
        }.padding()
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Manual sanity check**

Build the Wren standalone (`./build-wren.sh debug`), launch, confirm: title says "Wren", 5 steps, Input Monitoring prompt (not Accessibility), tone phrases, download bar in footer. (Reset the flag first: `defaults delete com.thousandflowers.wren hasCompletedOnboarding_wren_v1`.)

- [ ] **Step 4: Commit**

```bash
git add UI/Onboarding/WrenOnboardingView.swift
git commit -m "feat(wren): full WrenOnboardingView flow (O1-O5)"
```

---

## Task 10: Thread styleDescriptor into completion prompt (C2)

**Files:**
- Modify: `Core/Completion/LlamaCompletionClient.swift:122-145` (chat path)
- Test: `Tests/OnboardingTests/SystemPromptTests.swift`

The `systemPrompt(userPrompt:styleDescriptor:)` already supports the param; the chat call site doesn't pass it. This wires it for the server/instruct path.

- [ ] **Step 1: Write the failing test**

Create `Tests/OnboardingTests/SystemPromptTests.swift`:

```swift
import XCTest
@testable import Parrot

final class SystemPromptTests: XCTestCase {
    func test_systemPrompt_includesStyleDescriptor_whenPresent() {
        let p = LlamaCompletionClient.systemPrompt(userPrompt: "", styleDescriptor: "User tends to write casual.")
        XCTAssertTrue(p.contains("User tends to write casual."))
    }
    func test_systemPrompt_omitsStyle_whenEmpty() {
        let p = LlamaCompletionClient.systemPrompt(userPrompt: "", styleDescriptor: "")
        XCTAssertFalse(p.contains("User tends"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails OR passes**

Run: `swift test --filter SystemPromptTests`
Expected: PASS already (the function supports the param). This test guards the contract; the real change is the call site below.

- [ ] **Step 3: Pass the descriptor at the chat call site**

In `Core/Completion/LlamaCompletionClient.swift`, in `chatCompletion(...)`, fetch the descriptor and pass it. Replace:

```swift
            "messages": [["role": "system", "content": Self.systemPrompt(userPrompt: effectivePrompt)],
```

with (add the `await` fetch just before building `payload`):

```swift
        let styleDescriptor = await CompletionLearningStore.shared.styleDescriptor()
```

and in the payload:

```swift
            "messages": [["role": "system", "content": Self.systemPrompt(userPrompt: effectivePrompt, styleDescriptor: styleDescriptor)],
```

(`chatCompletion` is already `async`, so `await` is allowed.)

- [ ] **Step 4: Build + test**

Run: `swift build && swift test --filter SystemPromptTests`
Expected: builds clean, test PASS.

- [ ] **Step 5: Commit**

```bash
git add Core/Completion/LlamaCompletionClient.swift Tests/OnboardingTests/SystemPromptTests.swift
git commit -m "feat(completion): inject StyleProfile descriptor into chat prompt (C2)"
```

---

## Task 11: ToneTuneUpScheduler (pure due/not-due)

**Files:**
- Create: `Core/Completion/ToneTuneUpScheduler.swift`
- Test: `Tests/OnboardingTests/ToneTuneUpSchedulerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/OnboardingTests/ToneTuneUpSchedulerTests.swift`:

```swift
import XCTest
@testable import Parrot

final class ToneTuneUpSchedulerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func test_off_isNeverDue() {
        XCTAssertFalse(ToneTuneUpScheduler.isDue(cadence: .off, lastRun: nil, now: now))
        XCTAssertFalse(ToneTuneUpScheduler.isDue(cadence: .off, lastRun: now.addingTimeInterval(-999_999), now: now))
    }
    func test_neverRun_isDue_whenEnabled() {
        XCTAssertTrue(ToneTuneUpScheduler.isDue(cadence: .daily, lastRun: nil, now: now))
    }
    func test_daily_dueAfter24h() {
        XCTAssertFalse(ToneTuneUpScheduler.isDue(cadence: .daily, lastRun: now.addingTimeInterval(-23*3600), now: now))
        XCTAssertTrue(ToneTuneUpScheduler.isDue(cadence: .daily, lastRun: now.addingTimeInterval(-25*3600), now: now))
    }
    func test_weekly_dueAfter7d() {
        XCTAssertFalse(ToneTuneUpScheduler.isDue(cadence: .weekly, lastRun: now.addingTimeInterval(-6*86400), now: now))
        XCTAssertTrue(ToneTuneUpScheduler.isDue(cadence: .weekly, lastRun: now.addingTimeInterval(-8*86400), now: now))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ToneTuneUpSchedulerTests`
Expected: FAIL — undefined.

- [ ] **Step 3: Implement**

Create `Core/Completion/ToneTuneUpScheduler.swift`:

```swift
import Foundation

/// How often Wren resurfaces the optional tone practice. Raw values persist in UserDefaults.
enum ToneTuneUpCadence: String, CaseIterable, Sendable {
    case off, daily, weekly
    var interval: TimeInterval? {
        switch self {
        case .off: return nil
        case .daily: return 24 * 3600
        case .weekly: return 7 * 24 * 3600
        }
    }
}

/// Pure decision: is a tone tune-up due? Injectable `now` for tests.
enum ToneTuneUpScheduler {
    static func isDue(cadence: ToneTuneUpCadence, lastRun: Date?, now: Date = Date()) -> Bool {
        guard let interval = cadence.interval else { return false }   // .off
        guard let last = lastRun else { return true }                 // never run
        return now.timeIntervalSince(last) >= interval
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ToneTuneUpSchedulerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Core/Completion/ToneTuneUpScheduler.swift Tests/OnboardingTests/ToneTuneUpSchedulerTests.swift
git commit -m "feat(completion): ToneTuneUpScheduler pure due/not-due logic"
```

---

## Task 12: Cadence setting (PreferencesStore + Constants)

**Files:**
- Modify: `App/Constants.swift` (add UserDefaults keys)
- Modify: `Infra/PreferencesStore.swift` (cadence + last-run accessors)
- Test: `Tests/OnboardingTests/CadencePrefTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/OnboardingTests/CadencePrefTests.swift`:

```swift
import XCTest
@testable import Parrot

final class CadencePrefTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.toneTuneUpCadence)
    }
    func test_default_isOff() {
        XCTAssertEqual(PreferencesStore.shared.toneTuneUpCadence, .off)
    }
    func test_roundTrips() {
        PreferencesStore.shared.toneTuneUpCadence = .weekly
        XCTAssertEqual(PreferencesStore.shared.toneTuneUpCadence, .weekly)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CadencePrefTests`
Expected: FAIL — keys/accessors undefined.

- [ ] **Step 3: Add the keys**

In `App/Constants.swift`, inside the `UserDefaultsKey` enum (where the other `static let` string keys live), add:

```swift
        static let toneTuneUpCadence = "toneTuneUpCadence"
        static let toneTuneUpLastRun = "toneTuneUpLastRun"
```

- [ ] **Step 4: Add the accessors**

In `Infra/PreferencesStore.swift`, near the other completion-related computed vars, add:

```swift
    var toneTuneUpCadence: ToneTuneUpCadence {
        get { ToneTuneUpCadence(rawValue: string(Constants.UserDefaultsKey.toneTuneUpCadence, fallback: "off")) ?? .off }
        set { set(newValue.rawValue, for: Constants.UserDefaultsKey.toneTuneUpCadence) }
    }
    var toneTuneUpLastRun: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: Constants.UserDefaultsKey.toneTuneUpLastRun)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, for: Constants.UserDefaultsKey.toneTuneUpLastRun) }
    }
```

Note: confirm the `string(_:fallback:)` helper signature matches existing usage in the file (e.g. line 24). If `set(_:for:)` does not accept a `Double`/`TimeInterval`, use `UserDefaults.standard.set(...)` directly as shown.

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter CadencePrefTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add App/Constants.swift Infra/PreferencesStore.swift Tests/OnboardingTests/CadencePrefTests.swift
git commit -m "feat(completion): tone tune-up cadence + last-run preferences"
```

---

## Task 13: Cadence picker in CompletionTab

**Files:**
- Modify: `UI/CompletionTab.swift`

UI — verify by build. Read the file first to match its section/row style; the snippet below is a self-contained `Section`/row that follows the SwiftUI `Form` idiom used there.

- [ ] **Step 1: Add the picker**

In `UI/CompletionTab.swift`, add this control within the tab's form (place it after the existing completion toggles; bind to `prefs`):

```swift
            Picker("Tone tune-up", selection: Binding(
                get: { prefs.toneTuneUpCadence },
                set: { prefs.toneTuneUpCadence = $0 }
            )) {
                Text("Off").tag(ToneTuneUpCadence.off)
                Text("Daily").tag(ToneTuneUpCadence.daily)
                Text("Weekly").tag(ToneTuneUpCadence.weekly)
            }
            .help("Occasionally finish a few phrases so Wren keeps learning your tone.")
```

If `CompletionTab` does not already hold a `prefs` reference, read its declaration and use the same store it uses for the other completion controls.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add UI/CompletionTab.swift
git commit -m "feat(wren): tone tune-up cadence picker in CompletionTab"
```

---

## Task 14: Surface the recurring tune-up at launch

**Files:**
- Modify: `App/AppDelegate.swift` (Wren-only, after onboarding check)
- Modify: `UI/Onboarding/WrenOnboardingView.swift` (add a standalone presenter for the tune-up window)

Reuses `TonePracticeView`. On launch, if Wren + cadence enabled + due, open a small window with a rotating phrase subset; on learn, stamp `toneTuneUpLastRun`. Verify by build + manual.

- [ ] **Step 1: Add a tune-up window presenter**

Append to `UI/Onboarding/WrenOnboardingView.swift`:

```swift
import AppKit

/// Opens the tone practice as a standalone window for the recurring tune-up.
@MainActor
enum ToneTuneUpPresenter {
    private static var window: NSWindow?

    static func presentIfDue() {
        guard AppMode.current.showsCompletion else { return }
        let prefs = PreferencesStore.shared
        guard ToneTuneUpScheduler.isDue(cadence: prefs.toneTuneUpCadence,
                                        lastRun: prefs.toneTuneUpLastRun) else { return }
        present()
    }

    static func present() {
        if let w = window { w.makeKeyAndOrderFront(nil); return }
        // Rotate by day count so each tune-up shows a fresh slice.
        let seed = Int(Date().timeIntervalSince1970 / 86400)
        let phrases = TonePhrases.rotating(count: 3, seed: seed)
        let root = TonePracticeView(phrases: phrases, onLearned: { _ in
            PreferencesStore.shared.toneTuneUpLastRun = Date()
            window?.close(); window = nil
        })
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Tone tune-up — Wren"
        w.center(); w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: root.frame(width: 560, height: 420))
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 2: Call it at launch**

In `App/AppDelegate.swift`, after `OnboardingController.shared.showIfNeeded()` (line ~104), add:

```swift
        ToneTuneUpPresenter.presentIfDue()
```

(It is internally gated to Wren + due, so the call is safe in both modes.)

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 4: Manual check**

`defaults write com.thousandflowers.wren toneTuneUpCadence -string daily`, ensure `toneTuneUpLastRun` is unset, launch Wren → tune-up window appears with 3 phrases; complete → window closes, `defaults read com.thousandflowers.wren toneTuneUpLastRun` is set.

- [ ] **Step 5: Commit**

```bash
git add App/AppDelegate.swift UI/Onboarding/WrenOnboardingView.swift
git commit -m "feat(wren): surface recurring tone tune-up when due"
```

---

## Task 15: Full suite + cleanup

- [ ] **Step 1: Run the whole test suite**

Run: `swift test`
Expected: all green (existing Phase 0 suite + new `OnboardingTests`).

- [ ] **Step 2: Remove the old NSAlert duplication (optional polish)**

The launch-time "Nessun modello installato" `NSAlert` in `App/AppDelegate.swift:61-83` now overlaps with onboarding's background download. Leave it as the fallback for users who Skip onboarding, but gate it so it does not fire while onboarding is still showing:

```swift
        if mode.showsCompletion && PreferencesStore.shared.inlineCompletionEnabled
           && UserDefaults.standard.bool(forKey: OnboardingController.completionKey(for: .wren)) {
```

(Only show the alert once onboarding is complete.)

- [ ] **Step 3: Build the Wren standalone and smoke-test end to end**

Run: `./build-wren.sh debug` then launch, reset `hasCompletedOnboarding_wren_v1`, walk the full flow.

- [ ] **Step 4: Commit**

```bash
git add App/AppDelegate.swift
git commit -m "chore(wren): gate no-model alert to post-onboarding"
```

---

## Self-Review (completed during planning)

**Spec coverage:**
- O1 mode-gating → Tasks 2, 9. O2 Input Monitoring → Task 9 (step 1). O3 tone capture → Tasks 4–6, 8, 9. O4 background download → Tasks 7, 9. O5 live-demo/ready → Task 9 (ReadyStep). B1/B2 branding → Task 1. C2 prompt injection → Task 10. Recurring tune-up → Tasks 11–14. Scaffold extraction → Task 3. Optionality → Task 8 (Skip + optional sections). Curated case-spanning phrases → Task 6. Per-mode key → Task 2.
- Edge cases: download fail → Task 9 ReadyStep `.failed`; Input Monitoring denied → Task 9 ReadyStep warning; already-installed model → Task 9 `prepareDownload` guard; skip → onComplete sets key; reopened idempotent → `seed` additive (existing) + coordinator no-restart (Task 7).

**Type consistency:** `ModelDownloadCoordinator.Phase`, `.start(modelID:url:sha:)`, `ToneSeeder.learn(phraseCompletions:pastedText:store:)` / `.learn(fromFiles:store:)`, `ToneTuneUpCadence`, `TonePhrases.rotating(count:seed:)`, `OnboardingController.completionKey(for:)`, `CompletionLearningStore.recordStyleSample(from:)` — used consistently across tasks.

**Open verification (flagged in-task, not placeholders):** PreferencesStore `string(_:fallback:)` / `set(_:for:)` signatures (Task 12 note); `CompletionTab` `prefs` reference + form idiom (Task 13 note); `kIOHIDAccessTypeGranted` constant name (used in `TabInterceptor.swift` — confirm exact spelling there). These are "match the existing code" checks, with the existing reference cited.
</content>
