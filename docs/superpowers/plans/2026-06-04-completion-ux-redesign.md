# Completion Quality & Responsiveness — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Wren's inline completion coherent (no restating), language-correct, fast (near real-time), and native-feeling — without changing the on-device model.

**Architecture:** Four independent, sequenced workstreams on the existing pipeline: (A) deterministic anti-repetition + (D) granular language filter in `CompletionPostprocessor`; (B1) mid-word vs phrase generation; (B2/B3) accepted-branch speculative pre-compute + activation TTL; (C) overlay font-match/blur + atomic insert. TDD for the pure postprocessing units; build + **sequential** helper tests for model/IO units (never pipe multiple requests at once — that triggers the helper's cross-process supersede).

**Tech Stack:** Swift 5.10, SwiftPM (`swift test` → `ParrotTests`), llama.cpp via `CLlama`, AppKit (NSPanel/NSVisualEffectView), Accessibility (AXUIElement).

**Spec:** `docs/superpowers/specs/2026-06-04-completion-ux-redesign-design.md`

**Working directory:** `core/` (the shared submodule). All paths below are relative to it.

---

## Phase A+D — Postprocessing (coherence + language). Pure, full TDD.

### Task 1: Fuzzy overlap strip (anti-repetition)

The model sometimes restates the user's text before continuing (`1984 è un libro di ` →
`il 1984 è un libro di George Orwell`). Strip the restated overlap, tolerating a few inserted leading
tokens.

**Files:**
- Modify: `Core/Completion/CompletionPostprocessor.swift`
- Test: `Tests/Tests.swift` (class `CompletionPostprocessorTests`)

- [ ] **Step 1: Write the failing test**

Add to `CompletionPostprocessorTests` in `Tests/Tests.swift`:

```swift
func test_stripsRestatedSentence_withInsertedLeadingWord() {
    let out = CompletionPostprocessor.clean(
        raw: "il 1984 è un libro di George Orwell",
        preContext: "1984 è un libro di ", maxWords: 6)
    XCTAssertEqual(out?.trimmingCharacters(in: .whitespaces), "George Orwell")
}

func test_stripsExactRestate() {
    let out = CompletionPostprocessor.clean(
        raw: "the cat sat on the mat",
        preContext: "the cat sat ", maxWords: 6)
    XCTAssertEqual(out?.trimmingCharacters(in: .whitespaces), "on the mat")
}

func test_keepsNormalContinuation_noOverlap() {
    let out = CompletionPostprocessor.clean(
        raw: " molto gentile.", preContext: "sei stato", maxWords: 6)
    XCTAssertEqual(out, " molto gentile.")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CompletionPostprocessorTests/test_stripsRestatedSentence_withInsertedLeadingWord`
Expected: FAIL (current echo-strip only matches exact prefix, so the "il "-prefixed restate is kept).

- [ ] **Step 3: Implement the fuzzy strip**

In `CompletionPostprocessor.swift`, replace the current step 1 (the `text.hasPrefix(preContext)` block)
with a call to a new helper, and add the helper at the bottom of the enum:

Replace:
```swift
        // 1. Some models echo the prompt/prefix back. Strip it if the output starts with it.
        if !preContext.isEmpty, text.hasPrefix(preContext) {
            text = String(text.dropFirst(preContext.count))
        }
```
with:
```swift
        // 1. Strip a restated overlap: models sometimes re-enunciate the user's text (optionally with
        //    a small inserted leading word like "il") before the real continuation.
        text = stripRestatedOverlap(suggestion: text, preContext: preContext)
```

Add this helper inside `enum CompletionPostprocessor` (before the closing brace):
```swift
    /// Removes any leading run of `suggestion` that merely restates the tail of `preContext`.
    /// Tolerates up to two inserted leading tokens in the suggestion (e.g. "il 1984 …").
    static func stripRestatedOverlap(suggestion: String, preContext: String) -> String {
        func norm(_ s: String) -> [String] {
            s.lowercased().split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        }
        let pre = norm(preContext)
        guard pre.count >= 2 else { return suggestion }
        let sugWords = suggestion.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let sugNorm = norm(suggestion)
        // The longest tail of preContext (≥2 words) that appears in the suggestion's first ~8 words,
        // allowing up to 2 leading filler words before the match.
        for tailLen in stride(from: min(pre.count, 12), through: 2, by: -1) {
            let tail = Array(pre.suffix(tailLen))
            for offset in 0...2 where offset + tail.count <= sugNorm.count {
                if Array(sugNorm[offset..<offset + tail.count]) == tail {
                    // Cut the suggestion's real words up to and including this overlap.
                    let cutWordCount = offset + tail.count
                    let kept = sugWords.drop(while: { $0.isEmpty }).dropFirst(cutWordCount)
                    return kept.joined(separator: " ")
                }
            }
        }
        return suggestion
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CompletionPostprocessorTests`
Expected: PASS (all three new tests + existing ones).

- [ ] **Step 5: Commit**

```bash
git add Core/Completion/CompletionPostprocessor.swift Tests/Tests.swift
git commit -m "feat(completion): fuzzy restated-overlap strip (anti-repetition)"
```

### Task 2: Granular language filter (script match)

Reject a suggestion only when it is entirely a *different* script than the context (Latin context →
all-CJK suggestion = reject). Supports Chinese users.

**Files:**
- Modify: `Core/Completion/CompletionPostprocessor.swift`
- Test: `Tests/Tests.swift` (`CompletionPostprocessorTests`)

- [ ] **Step 1: Write the failing test**

```swift
func test_rejectsScriptSwitch_latinToCJK() {
    let out = CompletionPostprocessor.clean(
        raw: "你好世界吗", preContext: "Ti scrivo per ", maxWords: 6)
    XCTAssertNil(out)
}
func test_allowsCJK_whenContextIsCJK() {
    let out = CompletionPostprocessor.clean(
        raw: "世界很大", preContext: "你好，", maxWords: 6)
    XCTAssertNotNil(out)
}
func test_allowsForeignNameMidLatin() {
    // a single non-Latin token inside a Latin suggestion is NOT a full script switch
    let out = CompletionPostprocessor.clean(
        raw: " di George Orwell", preContext: "un libro ", maxWords: 6)
    XCTAssertEqual(out, " di George Orwell")
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter CompletionPostprocessorTests/test_rejectsScriptSwitch_latinToCJK`
Expected: FAIL (current code only rejects *any* CJK regardless of context).

- [ ] **Step 3: Implement script-match**

In `CompletionPostprocessor.swift`, replace the current unconditional CJK-reject block:
```swift
        if text.unicodeScalars.contains(where: { s in
            (0x4E00...0x9FFF).contains(s.value) || (0x3400...0x4DBF).contains(s.value) ||
            (0x3040...0x30FF).contains(s.value) || (0xAC00...0xD7AF).contains(s.value) ||
            (0xF900...0xFAFF).contains(s.value) || (0xFF00...0xFFEF).contains(s.value)
        }) { return nil }
```
with:
```swift
        // Reject only an UNWANTED script switch: if the context is Latin and the suggestion is
        // (mostly) CJK, drop it; if the user writes CJK, CJK is fine. Granular, supports all users.
        if isCJKDominant(text) && !isCJKDominant(preContext) { return nil }
```
And add helper:
```swift
    private static func isCJKDominant(_ s: String) -> Bool {
        func isCJK(_ v: UInt32) -> Bool {
            (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) ||
            (0x3040...0x30FF).contains(v) || (0xAC00...0xD7AF).contains(v) ||
            (0xF900...0xFAFF).contains(v)
        }
        var letters = 0, cjk = 0
        for ch in s {
            for v in ch.unicodeScalars where ch.isLetter { letters += 1; if isCJK(v.value) { cjk += 1 }; break }
        }
        guard letters > 0 else { return false }
        return Double(cjk) / Double(letters) >= 0.5
    }
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter CompletionPostprocessorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Core/Completion/CompletionPostprocessor.swift Tests/Tests.swift
git commit -m "feat(completion): granular language filter (script match, supports CJK users)"
```

### Task 3: Bounded retry on empty/invalid

If cleaning yields nil, regenerate **once** with a different seed before giving up. Never loop.

**Files:**
- Modify: `Core/Completion/CompletionEngine.swift`
- Test: `Tests/SurfaceTests/` (new `RetryOnceTests.swift`) using a stub provider.

- [ ] **Step 1: Write the failing test**

Create `Tests/SurfaceTests/RetryOnceTests.swift`:
```swift
import XCTest
@testable import Parrot

final class RetryOnceTests: XCTestCase {
    actor StubProvider: CompletionProviding {
        var calls = 0
        let outputs: [String]
        init(_ o: [String]) { outputs = o }
        func complete(context: CompletionContext, maxWords: Int) async throws -> String {
            defer { calls += 1 }
            return calls < outputs.count ? outputs[calls] : ""
        }
        func callCount() -> Int { calls }
    }

    func test_retriesOnceWhenFirstIsEmpty() async {
        let stub = StubProvider(["", "ciao mondo"])
        let engine = CompletionEngine(provider: stub)
        let ctx = CompletionContext(preContext: "scrivo una ", postContext: "", language: "it")
        let s = await engine.suggest(context: ctx, maxWords: 4, allowCode: false, midWord: false)
        XCTAssertNotNil(s)
        let n = await stub.callCount()
        XCTAssertEqual(n, 2)   // first empty → one retry
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter RetryOnceTests`
Expected: FAIL (engine calls provider once, returns nil).

- [ ] **Step 3: Implement bounded retry**

In `CompletionEngine.suggest`, after the existing `guard let cleaned = ... else { ... }` that returns
nil, wrap the provider call + clean in a 2-iteration loop. Concretely, change the body so that when
`clean` returns nil/empty it retries once:
```swift
        for attempt in 0..<2 {
            let raw: String
            do { raw = try await provider.complete(context: context, maxWords: maxWords) }
            catch is CancellationError { return nil }
            catch { return nil }
            guard mine == generation else { return nil }
            if let cleaned = CompletionPostprocessor.clean(raw: raw, preContext: context.preContext,
                                                           maxWords: maxWords, allowCode: allowCode, midWord: midWord),
               !cleaned.isEmpty {
                return CompletionSuggestion(text: cleaned)
            }
            if attempt == 0 { continue }   // one retry, then give up
        }
        return nil
```
(Keep the `generation &+= 1; let mine = generation` lines above the loop. Remove the old single-shot
`raw`/`guard let cleaned` block this replaces.)

- [ ] **Step 4: Run tests**

Run: `swift test --filter RetryOnceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Core/Completion/CompletionEngine.swift Tests/SurfaceTests/RetryOnceTests.swift
git commit -m "feat(completion): bounded single retry when a suggestion cleans to empty"
```

---

## Phase B1 — Mid-word vs phrase generation

### Task 4: Choose generation mode by last char + cap tokens mid-word

Mid-word (last char is a letter): generate only the rest of the word (few tokens, stop at space).
Boundary: full phrase budget.

**Files:**
- Modify: `Core/Completion/CompletionController.swift` (compute mode; pass shorter `maxWords` when mid-word)
- Modify: `Core/Completion/WordBoundary.swift` (add a cheap last-char check; keep spell-check API for callers that want it)
- Test: `Tests/SurfaceTests/MidWordTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `MidWordTests.swift`:
```swift
func test_lastCharLetter_isMidWord() {
    XCTAssertTrue(WordBoundary.isMidWordFast(preContext: "rece"))
    XCTAssertTrue(WordBoundary.isMidWordFast(preContext: "ciao mond"))
}
func test_trailingSpaceOrPunct_isBoundary() {
    XCTAssertFalse(WordBoundary.isMidWordFast(preContext: "ciao "))
    XCTAssertFalse(WordBoundary.isMidWordFast(preContext: "ciao,"))
    XCTAssertFalse(WordBoundary.isMidWordFast(preContext: ""))
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter MidWordTests/test_lastCharLetter_isMidWord`
Expected: FAIL (`isMidWordFast` not defined).

- [ ] **Step 3: Implement `isMidWordFast` and use it**

In `WordBoundary.swift` add:
```swift
    /// Cheap boundary check: the caret is mid-word iff the char immediately before it is a letter.
    /// (Reliable and instant — unlike the spell-check `isMidWord`, which we no longer use for spacing.)
    static func isMidWordFast(preContext: String) -> Bool {
        guard let last = preContext.last else { return false }
        return last.isLetter
    }
```
In `CompletionController.requestSuggestion()`, where it currently computes
`let midWord = WordBoundary.isMidWord(preContext: preContext)`, change to:
```swift
        let midWord = WordBoundary.isMidWordFast(preContext: preContext)
        // Mid-word: only finish the current word → ask for a short budget so generation is fast.
        let effectiveMaxWords = midWord ? 1 : maxWords
```
and pass `effectiveMaxWords` to `CompletionEngine.shared.suggest(context:maxWords:allowCode:midWord:)`
instead of `maxWords`.

- [ ] **Step 4: Run tests**

Run: `swift test --filter MidWordTests`
Expected: PASS.

- [ ] **Step 5: Build the app + manual sequential check**

Run: `./build-wren.sh debug` then install/launch (see Appendix). Type `rece`, pause → expect a word
completion (e.g. `ption`); type `ciao ` (space), pause → expect a next-word/phrase suggestion.

- [ ] **Step 6: Commit**

```bash
git add Core/Completion/WordBoundary.swift Core/Completion/CompletionController.swift Tests/SurfaceTests/MidWordTests.swift
git commit -m "feat(completion): mid-word mode (finish the word, lighter compute) vs phrase at boundary"
```

---

## Phase D-prevention — Language logit-bias in the helper

### Task 5: Bias against CJK tokens when context is Latin

Prevent wrong-script output at generation time (fewer rejections/empties).

**Files:**
- Modify: `CompletionHelper/main.swift` (add optional `latinOnly` flag to the request)
- Modify: `CompletionHelper/LlamaSession.swift` (apply a `logit_bias` sampler when `latinOnly`)
- Modify: `Core/Completion/HelperCompletionProvider.swift` (set `latinOnly` from context script)

- [ ] **Step 1: Extend the protocol with `latinOnly`**

In `CompletionHelper/main.swift`, change `Req`:
```swift
struct Req: Decodable { let prefix: String; let maxTokens: Int?; let id: Int?; let latinOnly: Bool? }
```
and pass it:
```swift
    let text = session.complete(prefix: req.prefix, maxTokens: req.maxTokens ?? 12,
                                latinOnly: req.latinOnly ?? false,
                                shouldCancel: { queue.hasNewer(than: seq) })
```
In `HelperCompletionProvider.swift`, change `Req` to add `let latinOnly: Bool` and set it when encoding:
```swift
    private struct Req: Encodable { let prefix: String; let maxTokens: Int; let id: Int; let latinOnly: Bool }
    ...
    let latinOnly = !pre.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3040...0x30FF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) }
    ... Req(prefix: pre, maxTokens: ..., id: reqID, latinOnly: latinOnly) ...
```

- [ ] **Step 2: Build the helper to verify it compiles**

Run: `swift build -c debug --arch arm64 --product ParrotCompletionHelper`
Expected: `Build complete!`

- [ ] **Step 3: Apply the logit bias in `LlamaSession.complete`**

Change the signature to accept `latinOnly: Bool = false`. After building the sampler chain, when
`latinOnly`, add a logit-bias sampler that strongly downweights CJK tokens. Build the bias array once
and cache it on the session:
```swift
    private lazy var cjkBias: [llama_logit_bias] = {
        var biases: [llama_logit_bias] = []
        let n = llama_vocab_n_tokens(vocab)
        for i in 0..<n {
            let p = piece(i)
            if p.unicodeScalars.contains(where: { (0x3400...0x9FFF).contains($0.value) ||
                (0x3040...0x30FF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) ||
                (0xF900...0xFAFF).contains($0.value) }) {
                biases.append(llama_logit_bias(token: i, bias: -100.0))
            }
        }
        return biases
    }()
```
In `complete`, after `llama_sampler_chain_add(smpl, llama_sampler_init_top_k(40))` etc., before the
dist sampler:
```swift
        if latinOnly, !cjkBias.isEmpty {
            cjkBias.withUnsafeBufferPointer { buf in
                llama_sampler_chain_add(smpl, llama_sampler_init_logit_bias(
                    llama_vocab_n_tokens(vocab), Int32(buf.count), buf.baseAddress))
            }
        }
```
(The `cjkBias` build scans the vocab once on first use, then is reused — negligible cost.)

- [ ] **Step 4: Build + sequential test**

Run: `swift build -c debug --arch arm64 --product ParrotCompletionHelper`
Then run the sequential helper test (Appendix) with an Italian prefix and confirm no CJK appears in
`"text"`. Expected: Latin-only output.

- [ ] **Step 5: Commit**

```bash
git add CompletionHelper/main.swift CompletionHelper/LlamaSession.swift Core/Completion/HelperCompletionProvider.swift
git commit -m "feat(completion): logit-bias against CJK when the context is Latin (language containment)"
```

---

## Phase B2/B3 — Speculative pre-compute + activation TTL

### Task 6: Accepted-branch pre-compute into the cache

When a suggestion `S` is shown for context `C`, pre-compute the completion for `C + S` in the
background and store it in `SuggestionCache`, keyed by the `C + S` context tail. The existing cache
lookup at the top of `requestSuggestion` then serves it instantly when the user accepts all of `S`.

**Files:**
- Modify: `Core/Completion/CompletionController.swift`
- Test: `Tests/SurfaceTests/SuggestionCacheTests.swift` (cache key/get/set behavior)

- [ ] **Step 1: Write the failing test (cache keying)**

Add to `SuggestionCacheTests.swift`:
```swift
func test_storesAndServesByContextTail() {
    let c = SuggestionCache()
    c.set(contextHash: String("scrivo una mail a".suffix(80)), suggestion: "Marco")
    XCTAssertEqual(c.get(contextHash: String("scrivo una mail a".suffix(80))), "Marco")
}
```

- [ ] **Step 2: Run to verify it passes or fails**

Run: `swift test --filter SuggestionCacheTests`
Expected: PASS if `SuggestionCache` already keys this way; if FAIL, align the test to the real API
(read `Core/Completion/SuggestionCache.swift` first and match its `get`/`set` signatures).

- [ ] **Step 3: Add the pre-compute call**

In `CompletionController.requestSuggestion()`, immediately after the successful engine path shows a
suggestion (`overlay.show(text: suggestion.text, atCaretRect: ax.caretRect)`), add a background
pre-compute of the accepted branch (guard against recursion with a flag):
```swift
        // Speculative: pre-compute the NEXT suggestion assuming the user accepts all of this one, so
        // accepting the whole thing feels instant. Fire-and-forget; result lands in the cache.
        let acceptedContext = preContext + suggestion.text
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let ctx = CompletionContext(preContext: acceptedContext, postContext: ax.postContext,
                                        language: PreferencesStore.shared.language)
            if let next = await CompletionEngine.shared.suggestForPrefetch(context: ctx, maxWords: maxWords, allowCode: allowCode) {
                await MainActor.run { self.cache.set(contextHash: String(acceptedContext.suffix(80)), suggestion: next.text) }
            }
        }
```
Add `suggestForPrefetch` to `CompletionEngine` (a variant of `suggest` that does NOT bump `generation`
— so it never cancels a live user request):
```swift
    func suggestForPrefetch(context: CompletionContext, maxWords: Int, allowCode: Bool) async -> CompletionSuggestion? {
        guard context.isUsable else { return nil }
        guard let raw = try? await provider.complete(context: context, maxWords: maxWords) else { return nil }
        guard let cleaned = CompletionPostprocessor.clean(raw: raw, preContext: context.preContext,
              maxWords: maxWords, allowCode: allowCode, midWord: false), !cleaned.isEmpty else { return nil }
        return CompletionSuggestion(text: cleaned)
    }
```

- [ ] **Step 4: Build + manual check**

Run: `./build-wren.sh debug`, install/launch. Type a phrase, accept the whole suggestion with `\`,
keep accepting — the next suggestion should appear with no visible wait (served from cache).

- [ ] **Step 5: Commit**

```bash
git add Core/Completion/CompletionController.swift Core/Completion/CompletionEngine.swift Tests/SurfaceTests/SuggestionCacheTests.swift
git commit -m "feat(completion): speculative accepted-branch pre-compute into cache"
```

### Task 7: Activation TTL (don't drop a fresh suggestion on spurious AX events)

**Files:**
- Modify: `Core/Completion/CompletionController.swift`

- [ ] **Step 1: Add a shown-at timestamp + TTL guard**

Add a stored `private var shownAt = Date.distantPast` set right after `overlay.show(...)`. In
`textChanged()`, if a suggestion is currently shown AND `Date().timeIntervalSince(shownAt) < 0.4`,
do **not** clear/hide it (skip the dim/clear) — only reset the debounce. This keeps a just-shown
suggestion alive for ~400 ms so a rapid `Tab` (or a spurious AXSelectedTextChanged) doesn't lose it.

```swift
    func textChanged() {
        guard isEnabled else { return }
        if current != nil, Date().timeIntervalSince(shownAt) < 0.4 {
            // keep the fresh suggestion visible; just (re)arm the debounce for the next compute
            debounce?.cancel()
            debounce = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(self?.adaptive.nextDelayMs(sinceLastKeystrokeMs: 0) ?? 140))
                guard !Task.isCancelled else { return }
                await self?.requestSuggestion()
            }
            return
        }
        ... (existing body) ...
    }
```

- [ ] **Step 2: Build + manual check**

Run: `./build-wren.sh debug`, install/launch. Type a phrase, pause for the suggestion, then press
`Tab` quickly several times — words should apply without the suggestion vanishing.

- [ ] **Step 3: Commit**

```bash
git add Core/Completion/CompletionController.swift
git commit -m "feat(completion): ~400ms activation TTL so rapid Tab never loses a fresh suggestion"
```

---

## Phase C — Overlay rendering + atomic insert

### Task 8: Match the field font + native blur backdrop

**Files:**
- Modify: `UI/CompletionOverlayWindow.swift`
- Modify: `Accessibility/AccessibilityBridge.swift` (expose focused-field font on `CompletionAXContext`)
- Modify: `Core/Completion/CompletionModels.swift` (add `fontSize`/`fontName` to `CompletionAXContext`)

- [ ] **Step 1: Add font fields to the AX context**

In `CompletionModels.swift`, extend `CompletionAXContext`:
```swift
struct CompletionAXContext: Sendable, Equatable {
    let preContext: String
    let postContext: String
    let caretRect: CGRect
    let isSecure: Bool
    var fontName: String? = nil
    var fontSize: CGFloat = 0
}
```
In `AccessibilityBridge.readCompletionContext`, after getting `element`, read the font:
```swift
        var fontName: String? = nil
        var fontSize: CGFloat = 0
        var fontRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXFont" as CFString, &fontRef) == .success,
           let dict = fontRef as? [String: Any] {
            fontName = dict["AXFontName"] as? String
            fontSize = (dict["AXFontSize"] as? CGFloat) ?? 0
        }
```
and pass `fontName: fontName, fontSize: fontSize` into the returned `CompletionAXContext`.

- [ ] **Step 2: Use the font + blur in the overlay**

In `CompletionOverlayWindow`, change `show(text:atCaretRect:)` to accept the font, and in `ensurePanel`
replace the layer-pill backdrop with an `NSVisualEffectView`:
```swift
    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isFloatingPanel = true; p.level = .statusBar
        p.backgroundColor = .clear; p.isOpaque = false; p.hasShadow = false; p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.setAccessibilityElement(false)
        let blur = NSVisualEffectView()
        blur.material = .hudWindow; blur.state = .active; blur.blendingMode = .behindWindow
        blur.wantsLayer = true; blur.layer?.cornerRadius = 5; blur.layer?.masksToBounds = true
        blur.addSubview(label); label.setAccessibilityElement(false)
        p.contentView = blur
        panel = p
        return p
    }
```
Change `show` to take `fontName: String?, fontSize: CGFloat` and build `baseFont`:
```swift
        let size = fontSize > 0 ? fontSize : (cachedFontSize > 0 ? cachedFontSize : readFontSize())
        let baseFont = (fontName.flatMap { NSFont(name: $0, size: size) }) ?? NSFont.systemFont(ofSize: size)
```
Update the call site in `CompletionController` to pass `ax.fontName, ax.fontSize`. Keep light text
(white at 0.72/0.98) — it reads on the blur.

- [ ] **Step 3: Build + manual check**

Run: `./build-wren.sh debug`, install/launch. Suggestions should use the field's font and sit on a
translucent blur readable in light and dark apps.

- [ ] **Step 4: Commit**

```bash
git add UI/CompletionOverlayWindow.swift Accessibility/AccessibilityBridge.swift Core/Completion/CompletionModels.swift
git commit -m "feat(completion): overlay matches field font + native blur backdrop"
```

### Task 9: Atomic insert on accept

Insert accepted text in one operation (clipboard-paste with save/restore) instead of synthesizing each
character; fall back to the current per-character path when paste is unavailable.

**Files:**
- Modify: `Accessibility/AccessibilityBridge.swift` (`insertCompletion`)

- [ ] **Step 1: Add a paste-based fast path**

In `insertCompletion(_:pid:)`, before the existing per-character synthesis, try a paste:
```swift
        // Fast path: paste the whole string at once (save + restore the user's clipboard).
        let pb = NSPasteboard.general
        let saved = pb.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data] in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let v = item.data(forType: t) { d[t] = v } }
            return d
        }
        pb.clearContents(); pb.setString(text, forType: .string)
        let ok = await pasteWithCmdV(pid: pid)   // existing CGEvent Cmd+V helper, or add one
        // restore clipboard after a short delay so the paste consumes the new value first
        try? await Task.sleep(for: .milliseconds(120))
        pb.clearContents()
        if let saved { for dict in saved { let it = NSPasteboardItem(); for (t, v) in dict { it.setData(v, forType: t) }; pb.writeObjects([it]) } }
        if ok { return true }
        // … fall through to existing per-character synthesis …
```
If no `pasteWithCmdV` helper exists, add one that posts ⌘V via `CGEvent` to `pid` (mirror the existing
keystroke-synthesis code in this file). Reuse the existing `PendingClipboardRestore` machinery if
present rather than the inline save/restore above.

- [ ] **Step 2: Build + manual check**

Run: `./build-wren.sh debug`, install/launch. Accept a multi-word suggestion with `\` — it should
appear in one step (not typed letter-by-letter), and the clipboard should be unchanged afterward.

- [ ] **Step 3: Commit**

```bash
git add Accessibility/AccessibilityBridge.swift
git commit -m "feat(completion): atomic paste-based insert on accept (clipboard preserved)"
```

---

## Appendix — build / run / sequential test commands

**Build + install + launch the debug app:**
```bash
./build-wren.sh debug
pkill -f "Wren.app/Contents/MacOS/Parrot"; pkill -f ParrotCompletionHelper; sleep 1
rm -rf /Applications/Wren.app && cp -R Wren.app /Applications/Wren.app
open /Applications/Wren.app
```
DIAG logs (debug build): `~/Library/Logs/Parrot/debug.log`.

**Sequential helper test (NEVER pipe many requests at once — that triggers cross-process supersede and
mis-measures quality). One request, wait, next:**
```bash
H=".build/arm64-apple-macosx/debug/ParrotCompletionHelper"
M="$HOME/Library/Application Support/Parrot/Models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
{ sleep 13; print '{"prefix":"Ti scrivo per dirti che ","maxTokens":14,"id":1,"latinOnly":true}'; sleep 8; } | "$H" "$M"
```

## Self-review notes
- Spec coverage: A→Task1+3, D→Task2+5, B1→Task4, B2→Task6, B3→Task7, C→Task8+9. All covered.
- Manual-test tasks (4,5,6,7,8,9) touch the model/UI and can't be pure-unit-tested; each has an exact
  build+observe step. Pure logic (1,2,3) is TDD.
- `SuggestionCache` get/set signatures (Task 6) must be confirmed against the real file before writing
  the test — noted in Step 2.
