# Wren Foundations (Phase 0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Wren's inline completion work in every macOS app with a verifiable latency budget, no clipboard hacks, and no hardcoded bundle lists.

**Architecture:** A `TextSurface` abstraction with three runtime-selected backends (NativeAX, ChromiumAX, Universal) chosen by a capability probe — never by app name. Pure helper units (LatencyTracer, SuggestionCache, TypedInputBuffer) are built and tested first, then the AX backends wrap the existing `AccessibilityBridge`, then `CompletionController` is rewired onto the abstraction with an adaptive-debounce + streaming latency pipeline and robustness invariants.

**Tech Stack:** Swift 5.9+, SwiftPM, AppKit, ApplicationServices (AX API), CoreGraphics (CGEventTap), XCTest. Runs on macOS 14+.

**Repo:** the shared `core` submodule (Parrot repo). Branch: `feat/wren-foundations`. Tests live under `Tests/`.

**Spec:** `docs/superpowers/specs/2026-05-31-wren-foundations-design.md`

---

## File Structure

New files:
- `Core/Completion/Surface/TextSurface.swift` — protocol + `SurfaceCapabilities` + `AXContext` value types
- `Core/Completion/Surface/NativeAXSurface.swift` — AX Cocoa backend
- `Core/Completion/Surface/ChromiumAXSurface.swift` — AXManualAccessibility flag + AX backend
- `Core/Completion/Surface/UniversalSurface.swift` — typed-buffer + keystroke backend
- `Core/Completion/Surface/SurfaceProbe.swift` — runtime backend selection
- `Core/Completion/Surface/TypedInputBuffer.swift` — reconstructs context from typed keys
- `Core/Completion/LatencyTracer.swift` — per-stage ms + p50/p95
- `Core/Completion/SuggestionCache.swift` — in-memory LRU
- `Tests/SurfaceTests/` — unit tests for the above

Modified:
- `Core/Completion/CompletionController.swift` — rewire onto `SurfaceProbe`, adaptive debounce, cache gate
- `Accessibility/AccessibilityBridge.swift` — expose low-level AX read/insert used by the backends; add per-call timeout
- `Shortcuts/TabInterceptor.swift` — feed typed keys to `TypedInputBuffer`
- `Package.swift` — add the `SurfaceTests` test target if test targets are declared per-module

> **Note for the implementer:** before writing tests, run `git grep -n "testTarget\|\.testTarget" Package.swift` and look at one existing file under `Tests/` to copy the project's exact XCTest import style and target layout. Match it. The test snippets below assume `import XCTest` and `@testable import <ModuleName>` — substitute the real module name.

---

## Task 1: LatencyTracer

**Files:**
- Create: `Core/Completion/LatencyTracer.swift`
- Test: `Tests/SurfaceTests/LatencyTracerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ParrotCore   // substitute the real module name

final class LatencyTracerTests: XCTestCase {
    func testRecordsPercentiles() {
        let tracer = LatencyTracer()
        for ms in [10.0, 20.0, 30.0, 40.0, 100.0] {
            tracer.record(stage: .total, milliseconds: ms)
        }
        XCTAssertEqual(tracer.percentile(.total, p: 50), 30.0, accuracy: 0.001)
        XCTAssertEqual(tracer.percentile(.total, p: 95), 100.0, accuracy: 0.001)
    }

    func testEmptyStageReturnsZero() {
        let tracer = LatencyTracer()
        XCTAssertEqual(tracer.percentile(.model, p: 95), 0.0)
    }

    func testRingBufferCaps() {
        let tracer = LatencyTracer(capacity: 3)
        for ms in [1.0, 2.0, 3.0, 4.0] { tracer.record(stage: .total, milliseconds: ms) }
        // oldest (1.0) evicted; p50 of [2,3,4] is 3
        XCTAssertEqual(tracer.percentile(.total, p: 50), 3.0, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LatencyTracerTests`
Expected: FAIL — `cannot find 'LatencyTracer' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Records per-stage latency samples and exposes percentiles. Thread-safe via a lock so it
/// can be written from the completion path and read from the diagnostics panel.
final class LatencyTracer: @unchecked Sendable {
    enum Stage: Hashable { case probe, readContext, cache, model, render, total }

    private let capacity: Int
    private var samples: [Stage: [Double]] = [:]
    private let lock = NSLock()

    init(capacity: Int = 512) { self.capacity = capacity }

    func record(stage: Stage, milliseconds: Double) {
        lock.lock(); defer { lock.unlock() }
        var arr = samples[stage] ?? []
        arr.append(milliseconds)
        if arr.count > capacity { arr.removeFirst(arr.count - capacity) }
        samples[stage] = arr
    }

    /// Nearest-rank percentile. Returns 0 for an empty stage.
    func percentile(_ stage: Stage, p: Double) -> Double {
        lock.lock(); defer { lock.unlock() }
        guard let arr = samples[stage], !arr.isEmpty else { return 0 }
        let sorted = arr.sorted()
        let rank = Int((p / 100.0) * Double(sorted.count - 1).rounded())
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LatencyTracerTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Core/Completion/LatencyTracer.swift Tests/SurfaceTests/LatencyTracerTests.swift
git commit -m "feat(completion): LatencyTracer with per-stage percentiles"
```

---

## Task 2: SuggestionCache (in-memory LRU)

**Files:**
- Create: `Core/Completion/SuggestionCache.swift`
- Test: `Tests/SurfaceTests/SuggestionCacheTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ParrotCore

final class SuggestionCacheTests: XCTestCase {
    func testHitReturnsStoredValue() {
        let cache = SuggestionCache(capacity: 2)
        cache.set(contextHash: "a", suggestion: "hello")
        XCTAssertEqual(cache.get(contextHash: "a"), "hello")
    }

    func testMissReturnsNil() {
        let cache = SuggestionCache(capacity: 2)
        XCTAssertNil(cache.get(contextHash: "nope"))
    }

    func testLRUEvictsLeastRecentlyUsed() {
        let cache = SuggestionCache(capacity: 2)
        cache.set(contextHash: "a", suggestion: "A")
        cache.set(contextHash: "b", suggestion: "B")
        _ = cache.get(contextHash: "a")          // touch a → b is now LRU
        cache.set(contextHash: "c", suggestion: "C")  // evicts b
        XCTAssertEqual(cache.get(contextHash: "a"), "A")
        XCTAssertNil(cache.get(contextHash: "b"))
        XCTAssertEqual(cache.get(contextHash: "c"), "C")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SuggestionCacheTests`
Expected: FAIL — `cannot find 'SuggestionCache' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Small in-memory LRU mapping a context hash to a cached completion string.
/// Sits in front of the on-disk learning store to guarantee the <50ms cache path.
final class SuggestionCache: @unchecked Sendable {
    private let capacity: Int
    private var store: [String: String] = [:]
    private var order: [String] = []   // front = least recently used
    private let lock = NSLock()

    init(capacity: Int = 256) { self.capacity = max(1, capacity) }

    func get(contextHash: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let value = store[contextHash] else { return nil }
        touch(contextHash)
        return value
    }

    func set(contextHash: String, suggestion: String) {
        lock.lock(); defer { lock.unlock() }
        store[contextHash] = suggestion
        touch(contextHash)
        while order.count > capacity {
            let evict = order.removeFirst()
            store[evict] = nil
        }
    }

    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SuggestionCacheTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Core/Completion/SuggestionCache.swift Tests/SurfaceTests/SuggestionCacheTests.swift
git commit -m "feat(completion): in-memory LRU SuggestionCache"
```

---

## Task 3: TypedInputBuffer

Reconstructs the field's recent text from the keys the user types, for the `UniversalSurface`
fallback. Pure logic — fed characters, produces a `pre` context string; reset on focus change
or navigation/edit keys.

**Files:**
- Create: `Core/Completion/Surface/TypedInputBuffer.swift`
- Test: `Tests/SurfaceTests/TypedInputBufferTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ParrotCore

final class TypedInputBufferTests: XCTestCase {
    func testAccumulatesTypedCharacters() {
        let buf = TypedInputBuffer()
        for c in "hello" { buf.type(character: c) }
        XCTAssertEqual(buf.preContext, "hello")
    }

    func testBackspaceRemovesLast() {
        let buf = TypedInputBuffer()
        for c in "helo" { buf.type(character: c) }
        buf.deleteBackward()
        buf.type(character: "p")
        XCTAssertEqual(buf.preContext, "help")
    }

    func testNavigationInvalidates() {
        let buf = TypedInputBuffer()
        for c in "hello" { buf.type(character: c) }
        buf.invalidate()                 // arrow key / click / paste / undo
        XCTAssertEqual(buf.preContext, "")
        buf.type(character: "x")
        XCTAssertEqual(buf.preContext, "x")
    }

    func testFocusChangeResets() {
        let buf = TypedInputBuffer()
        for c in "abc" { buf.type(character: c) }
        buf.focusChanged()
        XCTAssertEqual(buf.preContext, "")
    }

    func testCapsToMaxLength() {
        let buf = TypedInputBuffer(maxLength: 4)
        for c in "abcdef" { buf.type(character: c) }
        XCTAssertEqual(buf.preContext, "cdef")   // keeps the tail
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TypedInputBufferTests`
Expected: FAIL — `cannot find 'TypedInputBuffer' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Reconstructs the recently typed text of the focused field from keystrokes alone — no AX,
/// no clipboard. Used by UniversalSurface when AX exposes nothing. Per-focus; the buffer is
/// invalidated whenever the cursor may have moved in a way we cannot track (arrows, click,
/// paste, undo) so we never suggest on a wrong context.
final class TypedInputBuffer {
    private var chars: [Character] = []
    private let maxLength: Int

    init(maxLength: Int = 2048) { self.maxLength = max(1, maxLength) }

    var preContext: String { String(chars) }

    func type(character: Character) {
        chars.append(character)
        if chars.count > maxLength { chars.removeFirst(chars.count - maxLength) }
    }

    func deleteBackward() {
        if !chars.isEmpty { chars.removeLast() }
    }

    /// Cursor may have moved unpredictably (arrow/click/paste/undo). Drop everything.
    func invalidate() { chars.removeAll() }

    /// Focus moved to a different field. Drop everything.
    func focusChanged() { chars.removeAll() }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TypedInputBufferTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Core/Completion/Surface/TypedInputBuffer.swift Tests/SurfaceTests/TypedInputBufferTests.swift
git commit -m "feat(completion): TypedInputBuffer for AX-blind context reconstruction"
```

---

## Task 4: TextSurface protocol + value types

Defines the interface every backend implements and the capability struct the probe uses.

**Files:**
- Create: `Core/Completion/Surface/TextSurface.swift`
- Test: `Tests/SurfaceTests/TextSurfaceContractTests.swift`

- [ ] **Step 1: Write the failing test** (a fake surface proves the protocol shape compiles and behaves)

```swift
import XCTest
import CoreGraphics
@testable import ParrotCore

private final class FakeSurface: TextSurface {
    var stored = ""
    let caps: SurfaceCapabilities
    init(caps: SurfaceCapabilities) { self.caps = caps }
    func readContext() -> SurfaceContext? { caps.canRead ? SurfaceContext(pre: stored, post: "") : nil }
    func caretRect() -> CGRect? { caps.hasCaretRect ? CGRect(x: 1, y: 2, width: 0, height: 14) : nil }
    func insert(_ text: String) { stored += text }
    func replaceLastWord(wrong: String, with replacement: String) -> Bool {
        guard stored.hasSuffix(wrong) else { return false }
        stored.removeLast(wrong.count); stored += replacement; return true
    }
}

final class TextSurfaceContractTests: XCTestCase {
    func testInsertAppends() {
        let s = FakeSurface(caps: SurfaceCapabilities(canRead: true, canInsert: true, hasCaretRect: true))
        s.insert("abc")
        XCTAssertEqual(s.readContext()?.pre, "abc")
    }

    func testReplaceLastWordAbortsOnMismatch() {
        let s = FakeSurface(caps: SurfaceCapabilities(canRead: true, canInsert: true, hasCaretRect: true))
        s.insert("hello wirld")
        XCTAssertFalse(s.replaceLastWord(wrong: "world", with: "world!")) // mismatch → abort
        XCTAssertTrue(s.replaceLastWord(wrong: "wirld", with: "world"))
        XCTAssertEqual(s.readContext()?.pre, "hello world")
    }

    func testBlindSurfaceReturnsNilContext() {
        let s = FakeSurface(caps: SurfaceCapabilities(canRead: false, canInsert: true, hasCaretRect: false))
        XCTAssertNil(s.readContext())
        XCTAssertNil(s.caretRect())
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TextSurfaceContractTests`
Expected: FAIL — `cannot find type 'TextSurface' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import CoreGraphics

/// Text around the caret in the focused field.
struct SurfaceContext: Equatable {
    let pre: String
    let post: String
}

/// What a backend can do for the current focus. Decided by observation, never by bundle ID.
struct SurfaceCapabilities: Equatable {
    let canRead: Bool
    let canInsert: Bool
    let hasCaretRect: Bool
}

/// Single interface for reading context, locating the caret, and writing text into the
/// focused field. Backends: NativeAXSurface, ChromiumAXSurface, UniversalSurface.
protocol TextSurface: AnyObject {
    func readContext() -> SurfaceContext?
    func caretRect() -> CGRect?
    func insert(_ text: String)
    /// Returns false (and makes no change) if `wrong` is not the current trailing word.
    @discardableResult
    func replaceLastWord(wrong: String, with replacement: String) -> Bool
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TextSurfaceContractTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Core/Completion/Surface/TextSurface.swift Tests/SurfaceTests/TextSurfaceContractTests.swift
git commit -m "feat(completion): TextSurface protocol + capability/context value types"
```

---

## Task 5: SurfaceProbe (capability-driven backend selection)

Chooses a backend at runtime from observed capabilities, never the bundle ID. Tested with
injected factory closures so no real app/AX is needed.

**Files:**
- Create: `Core/Completion/Surface/SurfaceProbe.swift`
- Test: `Tests/SurfaceTests/SurfaceProbeTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ParrotCore

final class SurfaceProbeTests: XCTestCase {
    private func surface(_ canRead: Bool, _ hasCaret: Bool) -> TextSurface {
        final class S: TextSurface {
            let r: Bool; let c: Bool
            init(_ r: Bool, _ c: Bool) { self.r = r; self.c = c }
            func readContext() -> SurfaceContext? { r ? SurfaceContext(pre: "x", post: "") : nil }
            func caretRect() -> CGRect? { c ? .init(x: 0, y: 0, width: 0, height: 1) : nil }
            func insert(_ t: String) {}
            func replaceLastWord(wrong: String, with replacement: String) -> Bool { false }
        }
        return S(canRead, hasCaret)
    }

    func testPrefersNativeWhenItCanRead() {
        let probe = SurfaceProbe(
            makeNative: { self.surface(true, true) },
            makeChromium: { self.surface(true, true) },
            makeUniversal: { self.surface(true, false) },
            isChromium: { _ in false }
        )
        let chosen = probe.select(pid: 123)
        XCTAssertNotNil(chosen.readContext())   // native picked, can read
    }

    func testFallsBackToChromiumForChromiumProcessWhenNativeBlind() {
        var chromiumTried = false
        let probe = SurfaceProbe(
            makeNative: { self.surface(false, false) },          // native blind
            makeChromium: { chromiumTried = true; return self.surface(true, true) },
            makeUniversal: { self.surface(true, false) },
            isChromium: { _ in true }
        )
        _ = probe.select(pid: 123)
        XCTAssertTrue(chromiumTried)
    }

    func testFallsBackToUniversalWhenAllAXBlind() {
        let probe = SurfaceProbe(
            makeNative: { self.surface(false, false) },
            makeChromium: { self.surface(false, false) },
            makeUniversal: { self.surface(true, false) },        // universal always reads (typed buffer)
            isChromium: { _ in true }
        )
        let chosen = probe.select(pid: 123)
        XCTAssertNotNil(chosen.readContext())
        XCTAssertNil(chosen.caretRect())        // universal: degraded caret
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SurfaceProbeTests`
Expected: FAIL — `cannot find 'SurfaceProbe' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Picks the best TextSurface backend for the focused pid by *trying* them in order and
/// observing what each can do — never by matching the bundle identifier.
///
/// Order: NativeAX → (if Chromium process and native was blind) ChromiumAX → Universal.
/// Universal always succeeds (typed-input buffer), so `select` is total.
final class SurfaceProbe {
    private let makeNative: () -> TextSurface
    private let makeChromium: () -> TextSurface
    private let makeUniversal: () -> TextSurface
    private let isChromium: (pid_t) -> Bool

    init(makeNative: @escaping () -> TextSurface,
         makeChromium: @escaping () -> TextSurface,
         makeUniversal: @escaping () -> TextSurface,
         isChromium: @escaping (pid_t) -> Bool) {
        self.makeNative = makeNative
        self.makeChromium = makeChromium
        self.makeUniversal = makeUniversal
        self.isChromium = isChromium
    }

    func select(pid: pid_t) -> TextSurface {
        let native = makeNative()
        if native.readContext() != nil { return native }
        if isChromium(pid) {
            let chromium = makeChromium()      // applies AXManualAccessibility in its init
            if chromium.readContext() != nil { return chromium }
        }
        return makeUniversal()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SurfaceProbeTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Core/Completion/Surface/SurfaceProbe.swift Tests/SurfaceTests/SurfaceProbeTests.swift
git commit -m "feat(completion): SurfaceProbe — capability-driven backend selection"
```

---

## Task 6: AccessibilityBridge — per-call AX timeout

Add a timeout wrapper so a slow app can never hang the main actor; on expiry callers treat the
field as AX-blind. This is the primitive the NativeAX/ChromiumAX backends rely on.

**Files:**
- Modify: `Accessibility/AccessibilityBridge.swift`
- Test: `Tests/SurfaceTests/AXTimeoutTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ParrotCore

final class AXTimeoutTests: XCTestCase {
    func testReturnsValueBeforeTimeout() async {
        let r = await withAXTimeout(milliseconds: 100) { 42 }
        XCTAssertEqual(r, 42)
    }

    func testReturnsNilOnTimeout() async {
        let r = await withAXTimeout(milliseconds: 20) { () -> Int in
            Thread.sleep(forTimeInterval: 0.2)   // simulate a hung AX call
            return 1
        }
        XCTAssertNil(r)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AXTimeoutTests`
Expected: FAIL — `cannot find 'withAXTimeout' in scope`.

- [ ] **Step 3: Write minimal implementation** (add to `AccessibilityBridge.swift`, file scope)

```swift
/// Runs a blocking AX read on a background thread and returns nil if it does not finish within
/// `milliseconds`. Keeps a hung/slow app from freezing the completion path on the main actor.
func withAXTimeout<T>(milliseconds: Int, _ work: @escaping () -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask {
            await withCheckedContinuation { (cont: CheckedContinuation<T?, Never>) in
                DispatchQueue.global(qos: .userInitiated).async { cont.resume(returning: work()) }
            }
        }
        group.addTask {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            return Optional<T>.none
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AXTimeoutTests`
Expected: PASS (2 tests).

> **Note:** the timed-out background task is abandoned, not killed (AX has no cancellation). That
> is acceptable: it completes eventually and its result is discarded. Do not block on it.

- [ ] **Step 5: Commit**

```bash
git add Accessibility/AccessibilityBridge.swift Tests/SurfaceTests/AXTimeoutTests.swift
git commit -m "feat(a11y): withAXTimeout — AX reads can never hang the main actor"
```

---

## Task 7: NativeAXSurface (wrap existing AX read/insert)

Adapts the existing `AccessibilityBridge.completionContext` / `insertCompletion` /
`replaceLastWord` behind `TextSurface`, behind the timeout from Task 6.

**Files:**
- Create: `Core/Completion/Surface/NativeAXSurface.swift`
- Test: `Tests/SurfaceTests/NativeAXSurfaceTests.swift`

> Real AX cannot be exercised in a unit test. Inject the bridge calls as closures so the adapter
> logic (mapping `CompletionAXContext` → `SurfaceContext`, abort-on-mismatch) is tested without AX.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import ParrotCore

final class NativeAXSurfaceTests: XCTestCase {
    func testMapsContextAndCaret() {
        let s = NativeAXSurface(
            pid: 1,
            read: { (pre: "foo ", post: "bar", caret: CGRect(x: 5, y: 5, width: 0, height: 12), secure: false) },
            doInsert: { _ in true },
            doReplace: { _, _ in true }
        )
        XCTAssertEqual(s.readContext(), SurfaceContext(pre: "foo ", post: "bar"))
        XCTAssertEqual(s.caretRect(), CGRect(x: 5, y: 5, width: 0, height: 12))
    }

    func testSecureFieldReadsNil() {
        let s = NativeAXSurface(
            pid: 1,
            read: { (pre: "x", post: "", caret: .zero, secure: true) },
            doInsert: { _ in true }, doReplace: { _, _ in true })
        XCTAssertNil(s.readContext())   // never read secure fields
    }

    func testZeroCaretRectIsNil() {
        let s = NativeAXSurface(
            pid: 1,
            read: { (pre: "x", post: "", caret: .zero, secure: false) },
            doInsert: { _ in true }, doReplace: { _, _ in true })
        XCTAssertNil(s.caretRect())
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter NativeAXSurfaceTests`
Expected: FAIL — `cannot find 'NativeAXSurface' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import CoreGraphics

/// AX backend for native Cocoa apps. The actual AX calls are injected so the mapping logic is
/// unit-testable; the production wiring (Task 10) passes closures backed by AccessibilityBridge.
final class NativeAXSurface: TextSurface {
    typealias ReadResult = (pre: String, post: String, caret: CGRect, secure: Bool)

    private let pid: pid_t
    private let read: () -> ReadResult?
    private let doInsert: (String) -> Bool
    private let doReplace: (String, String) -> Bool

    init(pid: pid_t,
         read: @escaping () -> ReadResult?,
         doInsert: @escaping (String) -> Bool,
         doReplace: @escaping (String, String) -> Bool) {
        self.pid = pid
        self.read = read
        self.doInsert = doInsert
        self.doReplace = doReplace
    }

    func readContext() -> SurfaceContext? {
        guard let r = read(), !r.secure else { return nil }
        return SurfaceContext(pre: r.pre, post: r.post)
    }

    func caretRect() -> CGRect? {
        guard let r = read(), r.caret != .zero else { return nil }
        return r.caret
    }

    func insert(_ text: String) { _ = doInsert(text) }

    @discardableResult
    func replaceLastWord(wrong: String, with replacement: String) -> Bool {
        guard let r = read(), r.pre.hasSuffix(wrong) else { return false }  // abort on mismatch
        return doReplace(wrong, replacement)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter NativeAXSurfaceTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Core/Completion/Surface/NativeAXSurface.swift Tests/SurfaceTests/NativeAXSurfaceTests.swift
git commit -m "feat(completion): NativeAXSurface backend over AccessibilityBridge"
```

---

## Task 8: ChromiumAXSurface (AXManualAccessibility flag)

Same adapter logic as NativeAX, but its initializer first forces Chromium accessibility by
setting `AXManualAccessibility=true` on the app element. Tested by verifying the flag-setter
closure is invoked exactly once before the first read.

**Files:**
- Create: `Core/Completion/Surface/ChromiumAXSurface.swift`
- Test: `Tests/SurfaceTests/ChromiumAXSurfaceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import ParrotCore

final class ChromiumAXSurfaceTests: XCTestCase {
    func testSetsManualAccessibilityOnceBeforeRead() {
        var flagCalls = 0
        let s = ChromiumAXSurface(
            pid: 1,
            enableManualAX: { flagCalls += 1 },
            read: { (pre: "hi", post: "", caret: CGRect(x: 0, y: 0, width: 0, height: 10), secure: false) },
            doInsert: { _ in true }, doReplace: { _, _ in true })
        XCTAssertEqual(flagCalls, 1)                 // flag set in init
        XCTAssertEqual(s.readContext(), SurfaceContext(pre: "hi", post: ""))
        _ = s.readContext()
        XCTAssertEqual(flagCalls, 1)                 // never re-set
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ChromiumAXSurfaceTests`
Expected: FAIL — `cannot find 'ChromiumAXSurface' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import CoreGraphics

/// AX backend for Chromium/Electron apps. They ship with AX disabled until a client sets the
/// private `AXManualAccessibility` attribute to true on the app element; after that they expose a
/// real AX tree like a native app. We set the flag once in init, then behave like NativeAXSurface.
final class ChromiumAXSurface: TextSurface {
    typealias ReadResult = NativeAXSurface.ReadResult

    private let read: () -> ReadResult?
    private let doInsert: (String) -> Bool
    private let doReplace: (String, String) -> Bool

    init(pid: pid_t,
         enableManualAX: () -> Void,
         read: @escaping () -> ReadResult?,
         doInsert: @escaping (String) -> Bool,
         doReplace: @escaping (String, String) -> Bool) {
        enableManualAX()                 // force the AX tree on, once
        self.read = read
        self.doInsert = doInsert
        self.doReplace = doReplace
    }

    func readContext() -> SurfaceContext? {
        guard let r = read(), !r.secure else { return nil }
        return SurfaceContext(pre: r.pre, post: r.post)
    }

    func caretRect() -> CGRect? {
        guard let r = read(), r.caret != .zero else { return nil }
        return r.caret
    }

    func insert(_ text: String) { _ = doInsert(text) }

    @discardableResult
    func replaceLastWord(wrong: String, with replacement: String) -> Bool {
        guard let r = read(), r.pre.hasSuffix(wrong) else { return false }
        return doReplace(wrong, replacement)
    }
}
```

> **Production note (wired in Task 10):** `enableManualAX` sets the attribute on the AX app element:
> `AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ChromiumAXSurfaceTests`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add Core/Completion/Surface/ChromiumAXSurface.swift Tests/SurfaceTests/ChromiumAXSurfaceTests.swift
git commit -m "feat(completion): ChromiumAXSurface — force AXManualAccessibility"
```

---

## Task 9: UniversalSurface (typed-buffer read + keystroke insert)

The last-resort backend that guarantees "every app." Reads from a `TypedInputBuffer`; inserts via
an injected keystroke closure (production: `AccessibilityBridge.insertCompletion`). Caret rect via
an injected provider (production: AX caret → IMK rect → cursor estimate); may be nil → degraded
floating hint at the controller layer.

**Files:**
- Create: `Core/Completion/Surface/UniversalSurface.swift`
- Test: `Tests/SurfaceTests/UniversalSurfaceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import ParrotCore

final class UniversalSurfaceTests: XCTestCase {
    func testReadsFromTypedBuffer() {
        let buf = TypedInputBuffer()
        for c in "draf" { buf.type(character: c) }
        var inserted = ""
        let s = UniversalSurface(buffer: buf, doInsert: { inserted += $0 }, caretProvider: { nil })
        XCTAssertEqual(s.readContext(), SurfaceContext(pre: "draf", post: ""))
    }

    func testInsertGoesThroughKeystrokeAndUpdatesBuffer() {
        let buf = TypedInputBuffer()
        for c in "he" { buf.type(character: c) }
        var inserted = ""
        let s = UniversalSurface(buffer: buf, doInsert: { inserted += $0 }, caretProvider: { nil })
        s.insert("llo")
        XCTAssertEqual(inserted, "llo")
        XCTAssertEqual(s.readContext()?.pre, "hello")   // buffer reflects accepted text
    }

    func testReplaceLastWordAbortsOnMismatch() {
        let buf = TypedInputBuffer()
        for c in "say wrld" { buf.type(character: c) }
        let s = UniversalSurface(buffer: buf, doInsert: { _ in }, caretProvider: { nil })
        XCTAssertFalse(s.replaceLastWord(wrong: "world", with: "world"))
    }

    func testCaretFromProvider() {
        let s = UniversalSurface(buffer: TypedInputBuffer(),
                                 doInsert: { _ in },
                                 caretProvider: { CGRect(x: 9, y: 9, width: 0, height: 11) })
        XCTAssertEqual(s.caretRect(), CGRect(x: 9, y: 9, width: 0, height: 11))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UniversalSurfaceTests`
Expected: FAIL — `cannot find 'UniversalSurface' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import CoreGraphics

/// The "every app" guarantee. Reads context from keys the user typed (no AX, no clipboard) and
/// inserts via synthesized keystrokes, which work in any editable field. Caret rect comes from an
/// injected provider and may be nil, in which case the controller shows a floating hint instead of
/// inline ghost text.
final class UniversalSurface: TextSurface {
    private let buffer: TypedInputBuffer
    private let doInsert: (String) -> Void
    private let caretProvider: () -> CGRect?

    init(buffer: TypedInputBuffer,
         doInsert: @escaping (String) -> Void,
         caretProvider: @escaping () -> CGRect?) {
        self.buffer = buffer
        self.doInsert = doInsert
        self.caretProvider = caretProvider
    }

    func readContext() -> SurfaceContext? {
        let pre = buffer.preContext
        return pre.isEmpty ? nil : SurfaceContext(pre: pre, post: "")
    }

    func caretRect() -> CGRect? { caretProvider() }

    func insert(_ text: String) {
        doInsert(text)
        for c in text { buffer.type(character: c) }   // keep buffer consistent with the field
    }

    @discardableResult
    func replaceLastWord(wrong: String, with replacement: String) -> Bool {
        guard buffer.preContext.hasSuffix(wrong) else { return false }
        // delete wrong (backspaces) then type replacement — production doInsert handles deletes via
        // a control prefix; here we model the buffer side effect only.
        for _ in 0..<wrong.count { buffer.deleteBackward() }
        doInsert(replacement)
        for c in replacement { buffer.type(character: c) }
        return true
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter UniversalSurfaceTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Core/Completion/Surface/UniversalSurface.swift Tests/SurfaceTests/UniversalSurfaceTests.swift
git commit -m "feat(completion): UniversalSurface — typed-buffer read + keystroke insert"
```

---

## Task 10: Production wiring — build the real SurfaceProbe

Assemble a `SurfaceProbe` whose factory closures are backed by the real `AccessibilityBridge`
(behind `withAXTimeout`), the shared `TypedInputBuffer`, and `AppDetector.isChromium`. No new
behavior is invented here — this connects tested units to AX. Verified by build + the existing
suite, plus one smoke test that the assembly returns a non-nil surface.

**Files:**
- Modify: `Accessibility/AppDetector.swift` (add `isChromium(bundleID:) -> Bool` if absent — by
  querying the running app's executable, not a hardcoded list; see note)
- Create: `Core/Completion/Surface/SurfaceProbe+Live.swift`
- Test: `Tests/SurfaceTests/SurfaceProbeLiveTests.swift`

> **`isChromium` without a hardcoded list:** detect Chromium by probing, not naming. A process is
> "Chromium" for our purposes if setting `AXManualAccessibility` causes a previously-blind app
> element to start exposing AX children. Implementation: attempt the flag + a single child-count
> read; treat "was 0, now >0" as Chromium. This keeps the no-hardcoded-list rule. Keep the existing
> `ElectronFallbackHandler` list only as an optional fast-path hint, never as the sole decision.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ParrotCore

final class SurfaceProbeLiveTests: XCTestCase {
    func testLiveProbeAlwaysReturnsASurface() {
        let probe = SurfaceProbe.live(buffer: TypedInputBuffer())
        let surface = probe.select(pid: ProcessInfo.processInfo.processIdentifier)
        XCTAssertNotNil(surface)   // universal fallback guarantees non-nil
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SurfaceProbeLiveTests`
Expected: FAIL — `type 'SurfaceProbe' has no member 'live'`.

- [ ] **Step 3: Write minimal implementation**

```swift
import CoreGraphics
import ApplicationServices

extension SurfaceProbe {
    /// Wires the tested backends to the real AccessibilityBridge. Reads run behind withAXTimeout
    /// upstream (in the controller's async path); the synchronous closures here assume the values
    /// were already fetched. For the synchronous probe we do a best-effort direct read.
    static func live(buffer: TypedInputBuffer) -> SurfaceProbe {
        func nativeRead(_ pid: pid_t) -> NativeAXSurface.ReadResult? {
            guard let ctx = AccessibilityBridge.shared.completionContextSync(pid: pid) else { return nil }
            return (pre: ctx.preContext, post: ctx.postContext, caret: ctx.caretRect, secure: ctx.isSecure)
        }
        return SurfaceProbe(
            makeNative: { /* captured pid via closure factory below */
                fatalError("use makeNative(pid:)") },
            makeChromium: { fatalError("use makeChromium(pid:)") },
            makeUniversal: {
                UniversalSurface(buffer: buffer,
                                 doInsert: { text in Task { _ = await AccessibilityBridge.shared.insertCompletion(text, pid: 0) } },
                                 caretProvider: { nil }) },
            isChromium: { pid in AppDetector.shared.isChromiumProcess(pid: pid) }
        )
    }
}
```

> **Important:** the `SurfaceProbe` initializer from Task 5 takes zero-arg factories, but live
> backends need the `pid`. Before implementing this step, change `SurfaceProbe`'s factory closures
> from `() -> TextSurface` to `(pid_t) -> TextSurface` and update Task 5's tests accordingly
> (they pass `{ _ in self.surface(...) }`). Re-run `swift test --filter SurfaceProbeTests` to
> confirm they still pass. Then implement the live factories with real per-pid reads, the
> `enableManualAX` closure doing
> `AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)`,
> and `doInsert`/`doReplace` calling the existing `insertCompletion`/`replaceLastWord`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter "SurfaceProbeTests|SurfaceProbeLiveTests"`
Expected: PASS (both suites).

- [ ] **Step 5: Commit**

```bash
git add Accessibility/AppDetector.swift Core/Completion/Surface/SurfaceProbe+Live.swift Tests/SurfaceTests/SurfaceProbeLiveTests.swift
git commit -m "feat(completion): live SurfaceProbe wired to AccessibilityBridge"
```

---

## Task 11: Adaptive debounce + cache gate in CompletionController

Replace the fixed 120ms debounce with an adaptive one (starts ~40ms, grows under fast typing) and
put `SuggestionCache` as the first gate before any model call. Extract the debounce math into a
pure helper so it is unit-testable.

**Files:**
- Create: `Core/Completion/AdaptiveDebounce.swift`
- Modify: `Core/Completion/CompletionController.swift:30-40` (the `textChanged()` body)
- Test: `Tests/SurfaceTests/AdaptiveDebounceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ParrotCore

final class AdaptiveDebounceTests: XCTestCase {
    func testIdleUsesMinimum() {
        var d = AdaptiveDebounce(minMs: 40, maxMs: 200)
        XCTAssertEqual(d.nextDelayMs(sinceLastKeystrokeMs: 1000), 40)  // long pause → fast
    }

    func testFastTypingGrowsDelay() {
        var d = AdaptiveDebounce(minMs: 40, maxMs: 200)
        let fast = d.nextDelayMs(sinceLastKeystrokeMs: 20)              // hammering keys
        XCTAssertGreaterThan(fast, 40)
        XCTAssertLessThanOrEqual(fast, 200)
    }

    func testNeverExceedsMax() {
        var d = AdaptiveDebounce(minMs: 40, maxMs: 200)
        XCTAssertEqual(d.nextDelayMs(sinceLastKeystrokeMs: 0), 200)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AdaptiveDebounceTests`
Expected: FAIL — `cannot find 'AdaptiveDebounce' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Picks a debounce delay from how fast the user is typing. A long gap since the last keystroke
/// means they paused → fire fast (minMs). Rapid keystrokes → wait longer (toward maxMs) so we do
/// not burn inference on text that is about to change.
struct AdaptiveDebounce {
    let minMs: Int
    let maxMs: Int
    init(minMs: Int = 40, maxMs: Int = 200) { self.minMs = minMs; self.maxMs = maxMs }

    func nextDelayMs(sinceLastKeystrokeMs: Int) -> Int {
        // Map [0 .. maxMs] gap → [maxMs .. minMs] delay (inverse). Clamp outside.
        if sinceLastKeystrokeMs >= maxMs { return minMs }
        if sinceLastKeystrokeMs <= 0 { return maxMs }
        let fraction = Double(sinceLastKeystrokeMs) / Double(maxMs)        // 0..1
        let delay = Double(maxMs) - fraction * Double(maxMs - minMs)
        return Int(delay.rounded())
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AdaptiveDebounceTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Wire into CompletionController (no new test — covered by integration)**

In `CompletionController`, add `private var adaptive = AdaptiveDebounce()`, `private var lastKeystrokeAt = Date.distantPast`, `private let cache = SuggestionCache()`, `private let tracer = LatencyTracer()`. Replace the body of `textChanged()`:

```swift
func textChanged() {
    guard isEnabled else { return }
    let gap = Int(Date().timeIntervalSince(lastKeystrokeAt) * 1000)
    lastKeystrokeAt = Date()
    clearSuggestion()
    debounce?.cancel()
    let ms = adaptive.nextDelayMs(sinceLastKeystrokeMs: gap)
    debounce = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(ms))
        guard !Task.isCancelled else { return }
        await self?.requestSuggestion()
    }
}
```

In `requestSuggestion()`, after computing `ax.preContext`, add the cache gate before the learned-store lookup:

```swift
let cacheKey = String(ax.preContext.suffix(80))
if let hit = cache.get(contextHash: cacheKey) {
    current = CompletionSuggestion(text: hit, kind: .insert)
    currentPID = pid
    guard suggestionGen == gen else { return }
    TabInterceptor.setSuggestionVisible(true)
    overlay.show(text: hit, atCaretRect: ax.caretRect)
    return
}
```

And after a successful model suggestion, populate the cache: `cache.set(contextHash: cacheKey, suggestion: suggestion.text)`.

- [ ] **Step 6: Build + run full suite**

Run: `swift build && swift test`
Expected: build succeeds, all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Core/Completion/AdaptiveDebounce.swift Core/Completion/CompletionController.swift Tests/SurfaceTests/AdaptiveDebounceTests.swift
git commit -m "feat(completion): adaptive debounce + in-memory cache gate"
```

---

## Task 12: Feed typed keys into TypedInputBuffer from TabInterceptor

The CGEventTap already exists for Tab. Extend its handler to forward printable keydowns and
deletes to a shared `TypedInputBuffer`, and reset it on focus/app change. This makes the
`UniversalSurface` real.

**Files:**
- Modify: `Shortcuts/TabInterceptor.swift`
- Modify: `Core/Completion/CompletionController.swift` (own the shared `TypedInputBuffer`, call
  `focusChanged()` from the focus observer)
- Test: `Tests/SurfaceTests/TypedInputBufferTests.swift` (already covers the buffer; no AX test)

- [ ] **Step 1: Add a shared buffer and wire the tap (no new unit test — buffer logic already tested)**

In `CompletionController`: `let typedBuffer = TypedInputBuffer()`. In the focus-change observer (where `textChanged()` is triggered on focus switch), call `typedBuffer.focusChanged()`.

In `TabInterceptor`'s event-tap callback, for keydown events that are not the Tab accept and not a modifier chord:

```swift
if let chars = event.unicodeString(), !chars.isEmpty {
    CompletionController.shared.typedBuffer.type(character: Character(chars))
} else if event.getIntegerValueField(.keyboardEventKeycode) == kVKDelete {
    CompletionController.shared.typedBuffer.deleteBackward()
} else if isNavigationOrEditKey(event) {     // arrows, cmd-V, cmd-Z, cmd-arrows
    CompletionController.shared.typedBuffer.invalidate()
}
```

Add the helper `isNavigationOrEditKey(_:)` in `TabInterceptor` checking keycodes for arrows and the cmd-modified V/Z. (Reuse `kVKDelete` already referenced in `AccessibilityBridge`.)

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 3: Manual smoke test (documented, not automated)**

Open TextEdit, type a few words → ghost appears (NativeAX path unaffected). Open a terminal app
that exposes no AX value, type → confirm a suggestion can still be produced from the typed buffer
(check the `Logger.infra` debug line). This is the "every app" path proven live.

- [ ] **Step 4: Commit**

```bash
git add Shortcuts/TabInterceptor.swift Core/Completion/CompletionController.swift
git commit -m "feat(completion): feed typed keys into TypedInputBuffer for universal context"
```

---

## Task 13: Robustness — atomic insert verify + ghost cleanup

Harden accept and dismissal per the spec's robustness section.

**Files:**
- Modify: `Accessibility/AccessibilityBridge.swift` (`insertCompletion` post-verify)
- Modify: `Core/Completion/CompletionController.swift` (cleanup on transitions)
- Test: `Tests/SurfaceTests/InsertVerifyTests.swift`

- [ ] **Step 1: Write the failing test** (pure helper that decides whether a re-insert is needed)

```swift
import XCTest
@testable import ParrotCore

final class InsertVerifyTests: XCTestCase {
    func testNeedsRetryWhenTextAbsent() {
        XCTAssertTrue(InsertVerifier.needsKeystrokeFallback(expectedInsert: "llo", before: "he", after: "he"))
    }
    func testNoRetryWhenTextPresent() {
        XCTAssertFalse(InsertVerifier.needsKeystrokeFallback(expectedInsert: "llo", before: "he", after: "hello"))
    }
    func testNoRetryWhenAfterUnreadable() {
        XCTAssertFalse(InsertVerifier.needsKeystrokeFallback(expectedInsert: "llo", before: "he", after: nil))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter InsertVerifyTests`
Expected: FAIL — `cannot find 'InsertVerifier' in scope`.

- [ ] **Step 3: Write minimal implementation** (add `InsertVerifier` enum, file scope in AccessibilityBridge.swift)

```swift
/// Decides whether an AX insert silently failed and a one-shot keystroke fallback is needed.
/// Never loops: at most one retry, only when we can positively read that the text is missing.
enum InsertVerifier {
    static func needsKeystrokeFallback(expectedInsert: String, before: String, after: String?) -> Bool {
        guard let after else { return false }          // can't read → don't risk double insert
        if after == before { return true }             // nothing changed → AX insert failed
        return !after.contains(expectedInsert)         // changed but our text isn't there
    }
}
```

In `insertCompletion`, after the AX/keystroke insert, read the field once more and, if
`InsertVerifier.needsKeystrokeFallback(...)` is true, synthesize the keystrokes once.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter InsertVerifyTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Ghost cleanup on transitions (no new unit test — observer behavior)**

In `CompletionController`, ensure `dismiss()` is called from observers for: app deactivation
(`NSWorkspace.didDeactivateApplicationNotification`), left-mouse-down and scroll (via the existing
event tap → forward to `CompletionController.shared.dismiss()`), and Esc. Confirm `clearSuggestion()`
hides the overlay and resets `TabInterceptor.setSuggestionVisible(false)` (already implemented).

- [ ] **Step 6: Build + full suite**

Run: `swift build && swift test`
Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add Accessibility/AccessibilityBridge.swift Core/Completion/CompletionController.swift Tests/SurfaceTests/InsertVerifyTests.swift
git commit -m "feat: atomic insert verification + ghost cleanup on transitions"
```

---

## Task 14: Cancellation token to llama.cpp + keep-warm

Thread cancellation into the generation loop and add a keep-warm ping so the cold path stays
within budget.

**Files:**
- Modify: `CompletionHelper/LlamaSession.swift:88` (the `for _ in 0..<maxTokens` loop)
- Modify: `Core/Completion/LlamaCompletionClient.swift` (pass a cancel flag; add keep-warm ping)
- Test: `Tests/SurfaceTests/CancelFlagTests.swift`

- [ ] **Step 1: Write the failing test** (pure cancel-flag type used by the loop)

```swift
import XCTest
@testable import ParrotCore

final class CancelFlagTests: XCTestCase {
    func testStartsLive() { XCTAssertFalse(CancelFlag().isCancelled) }
    func testCancelSticks() {
        let f = CancelFlag(); f.cancel()
        XCTAssertTrue(f.isCancelled)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CancelFlagTests`
Expected: FAIL — `cannot find 'CancelFlag' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Thread-safe one-way cancellation flag checked inside the llama.cpp token loop so a new
/// keystroke can abandon in-flight generation immediately.
final class CancelFlag: @unchecked Sendable {
    private var cancelled = false
    private let lock = NSLock()
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CancelFlagTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Thread it through (no new unit test — wiring)**

In `LlamaSession.complete(...)`, accept a `cancel: CancelFlag` parameter and add
`if cancel.isCancelled { break }` at the top of the `for _ in 0..<maxTokens` loop. In
`LlamaCompletionClient`, create a `CancelFlag` per request, store it, and call `.cancel()` from
`cancelPending()`. Add a `keepWarm()` method that issues a 1-token generation every ~20s while Wren
is frontmost, called from a timer in `CompletionController` (only when `isEnabled`).

- [ ] **Step 6: Build + full suite**

Run: `swift build && swift test`
Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add CompletionHelper/LlamaSession.swift Core/Completion/LlamaCompletionClient.swift Tests/SurfaceTests/CancelFlagTests.swift
git commit -m "feat(completion): cancellation token into llama loop + keep-warm"
```

---

## Task 15: Wire SurfaceProbe into requestSuggestion + remove clipboard from completion path

Replace the direct `AccessibilityBridge.completionContext` call in `requestSuggestion()` with the
`SurfaceProbe` selection, and assert no clipboard usage remains in the completion path.

**Files:**
- Modify: `Core/Completion/CompletionController.swift:requestSuggestion`
- Test: `Tests/SurfaceTests/NoClipboardTests.swift` (source-level guard)

- [ ] **Step 1: Write the failing test** (guards against clipboard regressions in the completion path)

```swift
import XCTest

final class NoClipboardTests: XCTestCase {
    func testCompletionPathHasNoPasteboardUse() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let files = ["Core/Completion/CompletionController.swift",
                     "Core/Completion/Surface/UniversalSurface.swift",
                     "Core/Completion/Surface/NativeAXSurface.swift",
                     "Core/Completion/Surface/ChromiumAXSurface.swift"]
        for rel in files {
            let src = try String(contentsOf: root.appendingPathComponent(rel))
            XCTAssertFalse(src.contains("NSPasteboard"), "\(rel) must not touch the clipboard")
        }
    }
}
```

> Adjust the `deletingLastPathComponent()` chain so `root` is the repo root (the dir containing
> `Core/`). Verify by printing `root.path` once if needed.

- [ ] **Step 2: Run test to verify it fails OR passes**

Run: `swift test --filter NoClipboardTests`
Expected: PASS if the completion files are already clipboard-free (they should be). If it FAILS,
remove the offending `NSPasteboard` use from the completion path before continuing.

- [ ] **Step 3: Replace context acquisition with SurfaceProbe**

In `requestSuggestion()`, replace:

```swift
guard let ax = await AccessibilityBridge.shared.completionContext(pid: pid), !ax.isSecure else { ... }
```

with a probe-driven read behind the timeout:

```swift
let surface = SurfaceProbe.live(buffer: typedBuffer).select(pid: pid)
guard let ctx = await withAXTimeout(milliseconds: 50, { surface.readContext() }) ?? nil else {
    Logger.infra.debug("completion: no readable context")
    return
}
let caret = surface.caretRect()
```

Then use `ctx.pre` / `ctx.post` where `ax.preContext` / `ax.postContext` were used, and `caret`
(may be nil → floating-hint fallback, or skip ghost if you keep current behavior) where
`ax.caretRect` was used. Keep secure-field handling inside the surfaces (they return nil).

- [ ] **Step 4: Build + full suite**

Run: `swift build && swift test`
Expected: pass.

- [ ] **Step 5: Manual integration matrix**

Verify ghost text + accept in: TextEdit (native), Slack (Chromium), VSCode (Chromium), Safari
(web), Terminal (universal). Record pass/fail per app × {context, ghost, accept}. This is the
"every app" acceptance gate from the spec.

- [ ] **Step 6: Commit**

```bash
git add Core/Completion/CompletionController.swift Tests/SurfaceTests/NoClipboardTests.swift
git commit -m "feat(completion): route context through SurfaceProbe; assert clipboard-free path"
```

---

## Self-Review

**Spec coverage:**
- Works in every app → Tasks 4,5,9,10,12,15 (probe + universal fallback + integration matrix). ✅
- Latency budget → Tasks 1,2,11,14 (tracer, cache, adaptive debounce, cancel/keep-warm). ✅
- Zero clipboard / no hardcoded list → Tasks 5,10,15 (capability probe, isChromium by probing, NoClipboardTests). ✅
- Robustness → Tasks 6,13 (AX timeout, atomic insert verify, ghost cleanup). ✅
- Streaming early-render → partially deferred: the cache/early gates exist; full token-streaming
  early-render is wired via the CancelFlag loop in Task 14 but the incremental ghost-extend UI is
  minimal. **Acceptable for Phase 0** (budget met via cache + small model); flag for Phase 4 polish.

**Placeholder scan:** no TBD/TODO; every code step shows code. The two `fatalError` lines in Task 10
Step 3 are intentional scaffolding the same step's note replaces (factory signature change). ✅

**Type consistency:** `SurfaceContext`, `SurfaceCapabilities`, `NativeAXSurface.ReadResult`,
`TextSurface`, `SurfaceProbe.select(pid:)`, `TypedInputBuffer`, `CancelFlag`, `AdaptiveDebounce`,
`InsertVerifier`, `LatencyTracer.Stage` used consistently across tasks. One known refactor: Task 10
changes `SurfaceProbe` factories from `() ->` to `(pid_t) ->` and updates Task 5's tests — called
out explicitly in Task 10 Step 3. ✅

**Known integration assumptions to verify during execution** (not blockers):
- `AccessibilityBridge` exposes (or gains) `completionContextSync(pid:)` returning the same fields
  as `completionContext`. If only the async version exists, add a thin sync wrapper or make the
  probe async.
- `CGEvent.unicodeString()` helper may need to be written (read `keyboardGetUnicodeString`).
- Real module name for `@testable import` — confirm from `Package.swift` before Task 1.
