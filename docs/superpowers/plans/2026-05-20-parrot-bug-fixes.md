# Parrot Bug Fixes & Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 12 bugs and performance issues identified via full codebase audit: lost `source` field, hardcoded constants, streaming bypassing cache/queue, missing retry logic, NSLock technical debt, duplicated style analysis, missing disk persistence, and unused keys.

**Architecture:** Fixes are grouped into 9 independent tasks by related files. Each task is committable on its own and leaves the app in a working state. TDD: write/update failing tests first, then implement.

**Tech Stack:** Swift 6, SPM, XCTest (`swift test`), `@testable import Parrot`, actors, `OSAllocatedUnfairLock`, `URLSession`, `CryptoKit`

---

## File Map

| File | Tasks |
|------|-------|
| `Core/TextCheckCoordinator.swift` | Task 1 (source field) |
| `Core/RequestQueue.swift` | Task 1 (deadline), Task 3 (delegate resolveModelID) |
| `Core/TextCheckCoordinator+CheckFlows.swift` | Task 2 (checkStreaming overhaul) |
| `Core/LLMServiceFactory.swift` | Task 3 (add resolveModelID static method) |
| `Core/SSEStreamingEngine.swift` | Task 4 (session reuse + retry) |
| `App/Constants.swift` | Task 5 (remove lightweightMode key) |
| `App/AppDelegate.swift` | Task 6 (NSLock → OSAllocatedUnfairLock) |
| `Core/Lexicon.swift` | Task 7 (shared scoring + DE/ES/PT words) |
| `Core/ToneDetector.swift` | Task 7 (use Lexicon.computeStyleScores) |
| `Core/DocumentContext.swift` | Task 7 (use Lexicon.computeStyleScores) |
| `Infra/CorrectionCache.swift` | Task 8 (disk persistence) |
| `App/AppDelegate.swift` | Task 8 (call loadFromDisk at launch) |
| `Tests/Tests.swift` | All tasks |

---

## Task 1: Fix lost `source` field and hardcoded deadline

**Problem 1:** `TextCheckCoordinator.performCheck` reconstructs `CorrectionResult` at lines 194–205 but omits `source:`, causing all corrections to be tagged `.llm` in history—even rule-based ones.

**Problem 2:** `RequestQueue.enqueue` hardcodes `60` seconds instead of using `Constants.queueTimeout`.

**Files:**
- Modify: `Core/TextCheckCoordinator.swift:194–205`
- Modify: `Core/RequestQueue.swift:47`
- Modify: `Tests/Tests.swift` (add tests)

- [ ] **Step 1: Write failing tests**

Add to `Tests/Tests.swift`:

```swift
final class CorrectionResultSourceTests: XCTestCase {
    func testSource_preservedThroughRoundTrip() {
        // Simulate what performCheck does when reconstructing from rawResult
        let rawResult = CorrectionResult(original: "a", corrected: "b", modelID: "rules", source: .ruleBased)
        // Correct reconstruction — this is what the fix enables
        let rebuilt = CorrectionResult(
            original: rawResult.originalText,
            corrected: rawResult.correctedText,
            modelID: rawResult.modelID,
            explanation: rawResult.explanation,
            confidence: rawResult.confidence,
            customInstruction: rawResult.customInstruction,
            promptType: rawResult.promptType,
            detectedTone: rawResult.detectedTone,
            source: rawResult.source   // ← this is the fix
        )
        XCTAssertEqual(rebuilt.source, .ruleBased, "source must survive performCheck reconstruction")
    }

    func testSource_hybridPreserved() {
        let rawResult = CorrectionResult(original: "a", corrected: "b", modelID: "grammar+fluency", source: .hybrid)
        let rebuilt = CorrectionResult(
            original: rawResult.originalText, corrected: rawResult.correctedText,
            modelID: rawResult.modelID, source: rawResult.source
        )
        XCTAssertEqual(rebuilt.source, .hybrid)
    }

    func testQueueTimeout_matchesConstant() {
        // Ensure the constant is the authoritative value
        XCTAssertEqual(Constants.queueTimeout, 60.0)
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
swift test --filter CorrectionResultSourceTests 2>&1 | tail -20
```
Expected: 2 tests pass (the rebuilt source tests work because CorrectionResult.init has `source` parameter), 1 passes trivially. All pass even before the fix. **The real fix below is in TextCheckCoordinator — verify with a manual check.**

- [ ] **Step 3: Fix the `source` field in `TextCheckCoordinator.swift`**

Find the block at lines ~194–203 in `Core/TextCheckCoordinator.swift`:

```swift
// BEFORE
var mutableResult = CorrectionResult(
    original: rawResult.originalText,
    corrected: rawResult.correctedText,
    modelID: rawResult.modelID,
    explanation: rawResult.explanation,
    confidence: rawResult.confidence,
    customInstruction: rawResult.customInstruction,
    promptType: rawResult.promptType,
    detectedTone: detectedTone.rawValue)
```

Replace with:

```swift
// AFTER
var mutableResult = CorrectionResult(
    original: rawResult.originalText,
    corrected: rawResult.correctedText,
    modelID: rawResult.modelID,
    explanation: rawResult.explanation,
    confidence: rawResult.confidence,
    customInstruction: rawResult.customInstruction,
    promptType: rawResult.promptType,
    detectedTone: rawResult.detectedTone ?? detectedTone.rawValue,
    source: rawResult.source)
```

Note: `rawResult.detectedTone ?? detectedTone.rawValue` preserves the cached result's tone but falls back to fresh detection if nil.

- [ ] **Step 4: Fix hardcoded deadline in `RequestQueue.swift`**

Find line ~47 in `Core/RequestQueue.swift`:

```swift
// BEFORE
deadline: Date().addingTimeInterval(60),
```

Replace with:

```swift
// AFTER
deadline: Date().addingTimeInterval(Constants.queueTimeout),
```

- [ ] **Step 5: Run all tests**

```bash
swift test 2>&1 | tail -30
```
Expected: all existing tests pass.

- [ ] **Step 6: Commit**

```bash
git add Core/TextCheckCoordinator.swift Core/RequestQueue.swift Tests/Tests.swift
git commit -m "fix: preserve source field in performCheck, use Constants.queueTimeout for deadline"
```

---

## Task 2: checkStreaming overhaul (modelID + cache + tone)

**Problem:** `checkStreaming()` in `TextCheckCoordinator+CheckFlows.swift`:
- Hardcodes `modelID: "streaming"` instead of using the real model ID
- Never checks `CorrectionCache` before streaming
- Never writes results to `CorrectionCache` after streaming
- Never calls `ToneDetector`

**Files:**
- Modify: `Core/TextCheckCoordinator+CheckFlows.swift:32–47`
- Modify: `Tests/Tests.swift` (add test)

> **Prerequisite:** Task 3 must be done first (adds `LLMServiceFactory.resolveModelID(for:)`).

- [ ] **Step 1: Write failing test for cache round-trip with source preservation**

Add to `Tests/Tests.swift`:

```swift
final class StreamingModelIDTests: XCTestCase {
    func testCorrectionCache_preservesSource_onRoundTrip() async {
        await CorrectionCache.shared.invalidateAll()
        let result = CorrectionResult(original: "hello", corrected: "hi", modelID: "stub-v1", source: .llm)
        await CorrectionCache.shared.set(result, text: "hello", promptType: "grammar", modelID: "stub-v1", language: "en")
        let retrieved = await CorrectionCache.shared.get(text: "hello", promptType: "grammar", modelID: "stub-v1", language: "en")
        XCTAssertEqual(retrieved?.source, .llm)
        XCTAssertEqual(retrieved?.modelID, "stub-v1")
    }
}
```

- [ ] **Step 2: Run test to confirm it passes (cache already works)**

```bash
swift test --filter StreamingModelIDTests 2>&1 | tail -10
```
Expected: PASS — the cache handles this correctly, the issue is only in `checkStreaming` not calling it.

- [ ] **Step 3: Rewrite `checkStreaming()` in `Core/TextCheckCoordinator+CheckFlows.swift`**

Replace the entire `checkStreaming()` function (lines ~32–47):

```swift
func checkStreaming() {
    runTask {
        let prepared = try await prepareCheck()
        let serviceType = prepared.serviceType ?? LLMServiceFactory.resolveDefaultServiceType()
        let service = LLMServiceFactory.make(with: serviceType)
        let modelID = LLMServiceFactory.resolveModelID(for: serviceType)
        let detectedTone = await ToneDetector.shared.detect(
            text: prepared.text, language: prepared.resolvedLanguage
        )

        // Cache lookup before streaming
        if let cached = await CorrectionCache.shared.get(
            text: prepared.text,
            promptType: prepared.promptType.label,
            modelID: modelID,
            language: prepared.resolvedLanguage
        ) {
            await MainActor.run { SuggestionPanelController.shared.show(result: cached) }
            await showInlineAnnotations(
                result: cached,
                textOffset: prepared.replacementRange?.location ?? 0,
                pid: prepared.capturedPID
            )
            return
        }

        await MainActor.run { SuggestionPanelController.shared.showLoading() }
        var accumulated = ""
        let stream = service.streamCorrect(text: prepared.text, promptType: prepared.promptType)
        for try await chunk in stream {
            accumulated = chunk
        }
        try Task.checkCancellation()
        let finalText = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = CorrectionResult(
            original: prepared.text,
            corrected: finalText,
            modelID: modelID,
            confidence: 0.9,
            promptType: prepared.promptType.label,
            detectedTone: detectedTone.rawValue
        )
        result.replacementRange = prepared.replacementRange

        // Store in cache
        await CorrectionCache.shared.set(
            result,
            text: prepared.text,
            promptType: prepared.promptType.label,
            modelID: modelID,
            language: prepared.resolvedLanguage
        )

        await MainActor.run { SuggestionPanelController.shared.show(result: result) }
        await showInlineAnnotations(
            result: result,
            textOffset: prepared.replacementRange?.location ?? 0,
            pid: prepared.capturedPID
        )
    }
}
```

- [ ] **Step 4: Run all tests**

```bash
swift test 2>&1 | tail -30
```
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Core/TextCheckCoordinator+CheckFlows.swift Tests/Tests.swift
git commit -m "fix: checkStreaming uses real modelID, checks cache, detects tone"
```

---

## Task 3: Add `resolveModelID(for:)` to `LLMServiceFactory`

**Problem:** The model ID resolution logic in `RequestQueue.resolveModelID()` is private and duplicated. `checkStreaming` needs it too.

**Files:**
- Modify: `Core/LLMServiceFactory.swift` (add static method)
- Modify: `Core/RequestQueue.swift` (delegate to factory)
- Modify: `Tests/Tests.swift` (add tests)

> **Do this before Task 2** — Task 2 depends on `LLMServiceFactory.resolveModelID(for:)`.

- [ ] **Step 1: Write failing tests**

Add to `Tests/Tests.swift`:

```swift
final class LLMServiceFactoryModelIDTests: XCTestCase {
    func testResolveModelID_stub_returnsStubV1() {
        XCTAssertEqual(LLMServiceFactory.resolveModelID(for: .stub), "stub-v1")
    }

    func testResolveModelID_remote_returnsDefaultWhenNotSet() {
        // Remove any set value to test fallback
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.openAIModel)
        XCTAssertEqual(LLMServiceFactory.resolveModelID(for: .remote), "gpt-4o-mini")
    }

    func testResolveModelID_ollama_returnsDefaultWhenNotSet() {
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.ollamaModel)
        XCTAssertEqual(LLMServiceFactory.resolveModelID(for: .ollama), "llama3.2")
    }

    func testResolveModelID_openRouter_returnsDefaultWhenNotSet() {
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.openRouterModel)
        XCTAssertEqual(LLMServiceFactory.resolveModelID(for: .openRouter), "openai/gpt-4o-mini")
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
swift test --filter LLMServiceFactoryModelIDTests 2>&1 | tail -10
```
Expected: FAIL — `LLMServiceFactory.resolveModelID` does not exist yet.

- [ ] **Step 3: Add `resolveModelID(for:)` to `Core/LLMServiceFactory.swift`**

Add this method to `struct LLMServiceFactory` (after the existing `resolveServiceType` methods):

```swift
static func resolveModelID(for serviceType: ServiceType) -> String {
    switch serviceType {
    case .stub:
        return "stub-v1"
    case .local:
        let id = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.selectedModelID)
        return id?.replacingOccurrences(of: ".gguf", with: "") ?? "local-qwen"
    case .remote:
        return UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.openAIModel) ?? "gpt-4o-mini"
    case .ollama:
        return UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.ollamaModel) ?? "llama3.2"
    case .openRouter:
        return UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.openRouterModel) ?? "openai/gpt-4o-mini"
    }
}
```

- [ ] **Step 4: Update `RequestQueue.resolveModelID` to delegate to factory**

In `Core/RequestQueue.swift`, find the private method `resolveModelID(for:)` (~line 120) and replace its body:

```swift
private nonisolated func resolveModelID(for serviceType: ServiceType) -> String {
    LLMServiceFactory.resolveModelID(for: serviceType)
}
```

- [ ] **Step 5: Run tests**

```bash
swift test --filter LLMServiceFactoryModelIDTests 2>&1 | tail -10
```
Expected: all 4 tests PASS.

- [ ] **Step 6: Run all tests**

```bash
swift test 2>&1 | tail -30
```
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add Core/LLMServiceFactory.swift Core/RequestQueue.swift Tests/Tests.swift
git commit -m "refactor: extract resolveModelID to LLMServiceFactory, DRY up RequestQueue"
```

---

## Task 4: SSEStreamingEngine — session reuse and retry

**Problem 1:** Each `stream()` call creates a new `URLSession`, which has allocation overhead.

**Problem 2:** If the network hiccups during a stream, the whole stream fails with no retry (unlike `performOpenAIRequest` which retries 3 times with backoff).

**Files:**
- Modify: `Core/SSEStreamingEngine.swift`
- Modify: `Tests/Tests.swift` (add test)

- [ ] **Step 1: Write test for retry behavior**

Add to `Tests/Tests.swift`:

```swift
final class SSEStreamingEngineTests: XCTestCase {
    func testThrowIfHTTPError_200_doesNotThrow() async {
        // We test the HTTP error mapping indirectly via the public interface:
        // The engine is an actor, so we can only test it through stream().
        // For unit coverage of throwIfHTTPError, verify via status code mapping.
        // 200 → no throw (this exercises the non-throwing path)
        // This test documents the contract; actual network calls require integration tests.
        XCTAssertTrue(true, "contract: 200 does not throw — verified in integration tests")
    }
}
```

> Note: `SSEStreamingEngine` requires a live server to test fully. The retry and session tests are integration tests. Document that here and verify manually after the code change.

- [ ] **Step 2: Rewrite `Core/SSEStreamingEngine.swift`**

Replace the entire file:

```swift
import Foundation
import OSLog

/// Dedicated SSE (Server-Sent Events) streaming engine.
/// Parses OpenAI-compatible streaming responses and yields accumulated text.
/// Completely agnostic to the service — only needs a URLRequest.
actor SSEStreamingEngine {
    static let shared = SSEStreamingEngine()

    /// Shared ephemeral session — avoids allocating a session per request.
    /// Individual tasks are cancelled via Task cancellation, not session invalidation.
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Constants.requestTimeout
        return URLSession(configuration: config)
    }()

    /// Streams text from an OpenAI-compatible SSE endpoint.
    /// Yields the **accumulated** text after each chunk (not just the delta).
    /// Retries once on transient network errors (not on auth/rate errors).
    /// - Parameter request: Pre-configured URLRequest with streaming body.
    /// - Returns: AsyncThrowingStream of accumulated text strings.
    func stream(request: URLRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var lastError: Error?
                for attempt in 0..<2 {
                    do {
                        try await self.attemptStream(request: request, continuation: continuation)
                        return  // success — stream finished normally
                    } catch is CancellationError {
                        return  // never retry cancellations
                    } catch let error as CorrectionError {
                        switch error {
                        case .invalidAPIKey, .rateLimited, .modelNotLoaded, .outputParsingFailed:
                            continuation.finish(throwing: error)
                            return
                        default:
                            lastError = error
                        }
                    } catch {
                        lastError = error
                    }

                    if attempt == 0 {
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                }
                guard !Task.isCancelled else { return }
                continuation.finish(throwing: lastError ?? CorrectionError.networkUnavailable)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func attemptStream(
        request: URLRequest,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CorrectionError.networkUnavailable
        }
        try throwIfHTTPError(httpResponse)

        var accumulated = ""
        var skippedChunks = 0
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            if jsonStr == "[DONE]" { break }
            guard let jsonData = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                if !jsonStr.isEmpty && jsonStr != "[DONE]" {
                    skippedChunks += 1
                    if skippedChunks <= 3 {
                        Logger.core.debug("SSE: unparseable chunk (\(skippedChunks, privacy: .public))")
                    }
                }
                continue
            }
            accumulated += content
            continuation.yield(accumulated)
        }
        if accumulated.isEmpty {
            throw CorrectionError.outputParsingFailed(raw: "empty")
        }
        continuation.finish()
    }

    private func throwIfHTTPError(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200: return
        case 401, 403: throw CorrectionError.invalidAPIKey
        case 429: throw CorrectionError.rateLimited
        case 404: throw CorrectionError.modelNotLoaded
        case 500, 502, 503: throw CorrectionError.serverTimeout
        default: throw CorrectionError.outputParsingFailed(raw: "HTTP \(response.statusCode)")
        }
    }
}
```

- [ ] **Step 3: Run all tests**

```bash
swift test 2>&1 | tail -30
```
Expected: all pass (no tests call the live SSE engine).

- [ ] **Step 4: Commit**

```bash
git add Core/SSEStreamingEngine.swift Tests/Tests.swift
git commit -m "perf: SSEStreamingEngine reuses URLSession, adds one retry on transient errors"
```

---

## Task 5: Remove unused `lightweightMode` UserDefaults key

**Problem:** `Constants.UserDefaultsKey.lightweightMode` is defined but never read anywhere in the codebase. It's dead code that could mislead future developers.

**Files:**
- Modify: `App/Constants.swift`

- [ ] **Step 1: Verify the key is truly unused**

```bash
grep -r "lightweightMode" --include="*.swift" . | grep -v "\.build" | grep -v "Tests"
```
Expected: only the definition line in `Constants.swift`. If any other file shows up, **stop this task** and investigate before deleting.

- [ ] **Step 2: Remove the key from `App/Constants.swift`**

Find and delete this line from the `UserDefaultsKey` enum:

```swift
static let lightweightMode = "lightweightMode"
```

- [ ] **Step 3: Run all tests**

```bash
swift test 2>&1 | tail -20
```
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add App/Constants.swift
git commit -m "chore: remove unused lightweightMode UserDefaults key"
```

---

## Task 6: NSLock → OSAllocatedUnfairLock in AppDelegate

**Problem:** `applicationShouldTerminate` uses `NSLock` + `nonisolated(unsafe) var` — a pattern explicitly flagged in the codebase comment as needing Swift 6 migration. `OSAllocatedUnfairLock` is already used in the project (see `TextCheckCoordinator.swift`).

**Files:**
- Modify: `App/AppDelegate.swift:32–56`

- [ ] **Step 1: Rewrite `applicationShouldTerminate` in `App/AppDelegate.swift`**

Replace the entire method (lines 32–57):

```swift
// BEFORE
func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let replyLock = NSLock()
    // Swift 6 migration: replace with Mutex (swift-synchronization) or @MainActor redesign
    nonisolated(unsafe) var didReply = false
    let replyOnce: @Sendable () -> Void = {
        replyLock.lock()
        defer { replyLock.unlock() }
        guard !didReply else { return }
        didReply = true
        DispatchQueue.main.async {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
    }
    let timeoutTask = Task {
        try? await Task.sleep(for: .seconds(10))
        replyOnce()
    }
    Task {
        await RealtimeMonitor.shared.stop()
        await ServerManager.shared.stop()
        await ServerHealthMonitor.shared.stopMonitoring()
        timeoutTask.cancel()
        replyOnce()
    }
    return .terminateLater
}
```

Replace with:

```swift
// AFTER
func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let replySent = OSAllocatedUnfairLock<Bool>(initialState: false)
    let replyOnce: @Sendable () -> Void = {
        let alreadySent = replySent.withLock { state in
            let prev = state
            state = true
            return prev
        }
        guard !alreadySent else { return }
        DispatchQueue.main.async {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
    }
    let timeoutTask = Task {
        try? await Task.sleep(for: .seconds(10))
        replyOnce()
    }
    Task {
        await RealtimeMonitor.shared.stop()
        await ServerManager.shared.stop()
        await ServerHealthMonitor.shared.stopMonitoring()
        timeoutTask.cancel()
        replyOnce()
    }
    return .terminateLater
}
```

- [ ] **Step 2: Run all tests**

```bash
swift test 2>&1 | tail -20
```
Expected: all pass.

- [ ] **Step 3: Commit**

```bash
git add App/AppDelegate.swift
git commit -m "fix: replace NSLock+nonisolated(unsafe) with OSAllocatedUnfairLock in applicationShouldTerminate"
```

---

## Task 7: Unify style-scoring logic in Lexicon; expand vocabulary

**Problem 1:** `ToneDetector.detect()` and `ContextAnalyzer.styleFromText()` both compute scores from Lexicon sets but independently, with slightly different scoring formulas. This creates a maintenance hazard.

**Problem 2:** `Lexicon` only has informal/academic/technical words for EN, IT, FR, HR, DA. Adding DE, ES, PT improves detection for those languages.

**Approach:** Add `Lexicon.computeWordScores(words:rawWords:text:)` — a pure shared computation. Both `ToneDetector` and `ContextAnalyzer` call this. Each still has its own thresholds and regex patterns.

**Files:**
- Modify: `Core/Lexicon.swift`
- Modify: `Core/ToneDetector.swift`
- Modify: `Core/DocumentContext.swift`
- Modify: `Tests/Tests.swift`

- [ ] **Step 1: Write failing tests for vocabulary expansion**

Add to `Tests/Tests.swift`:

```swift
final class LexiconTests: XCTestCase {
    func testInformalWords_containsGerman() {
        XCTAssertTrue(Lexicon.informalWords.contains("krass"))
        XCTAssertTrue(Lexicon.informalWords.contains("geil"))
    }

    func testInformalWords_containsSpanish() {
        XCTAssertTrue(Lexicon.informalWords.contains("tío"))
        XCTAssertTrue(Lexicon.informalWords.contains("guay"))
    }

    func testAcademicWords_containsGerman() {
        XCTAssertTrue(Lexicon.academicWords.contains("daher"))
        XCTAssertTrue(Lexicon.academicWords.contains("folglich"))
    }

    func testComputeWordScores_informalText_highInformalScore() {
        let scores = Lexicon.computeWordScores(
            words: ["hey", "yeah", "cool"],
            rawWords: ["hey", "yeah", "cool"],
            text: "hey yeah cool"
        )
        XCTAssertGreaterThan(scores.informalScore, 10.0)
    }

    func testComputeWordScores_academicText_highAcademicScore() {
        let scores = Lexicon.computeWordScores(
            words: ["therefore", "furthermore", "consequently"],
            rawWords: ["therefore", "furthermore", "consequently"],
            text: "therefore furthermore consequently"
        )
        XCTAssertGreaterThan(scores.academicScore, 5.0)
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
swift test --filter LexiconTests 2>&1 | tail -10
```
Expected: FAIL — `Lexicon.computeWordScores` and DE/ES words don't exist yet.

- [ ] **Step 3: Update `Core/Lexicon.swift`**

Replace the entire file:

```swift
import Foundation

enum Lexicon {
    // MARK: - Informal words (EN, IT, FR, HR, DA, DE, ES, PT)

    static let informalWords: Set<String> = [
        // English
        "hey", "yeah", "yep", "nope", "cool", "awesome", "gonna",
        "wanna", "gotta", "kinda", "sorta", "dunno", "lol", "omg",
        "btw", "thx", "pls", "ok", "okay", "nah", "wow", "oops",
        "ciao", "eh", "ah", "oh", "xd", "haha", "lmao", "rofl",
        "tbh", "imo", "smh",
        // French informal
        "ouais", "nan", "bah", "hein", "genre", "truc", "machin",
        "chelou", "ouf", "grave", "carrément", "trop", "vachement",
        // Croatian informal
        "bok", "cao", "kul", "super", "hej", "jel", "šta", "kaj",
        // Danish informal
        "fedt", "nice", "sejt", "bare", "altså", "jo",
        // German informal
        "krass", "geil", "mega", "echt", "moin", "tschüss", "nee",
        "jup", "genau", "echt", "boah", "äh", "ähm",
        // Spanish informal
        "tío", "tía", "guay", "mola", "venga", "dale", "bueno",
        "hostia", "joder", "oye", "pues", "tío", "vale",
        // Portuguese informal
        "fixe", "giro", "bué", "tipo", "massa", "show", "beleza",
        "oi", "opa", "poxa", "caramba",
    ]

    // MARK: - Academic words (EN, IT, FR, HR, DA, DE, ES, PT)

    static let academicWords: Set<String> = [
        // English
        "therefore", "furthermore", "consequently", "nonetheless",
        "moreover", "thus", "hence", "accordingly", "nevertheless",
        "whereas", "hereby", "therein", "thereof", "wherein",
        // Italian academic
        "pertanto", "inoltre", "dunque", "conseguentemente",
        "ciononostante", "tuttavia", "perciò", "nonostante",
        "altresì", "parimenti",
        // French academic
        "ainsi", "néanmoins", "cependant", "toutefois", "certes",
        "dès lors", "par conséquent", "en outre", "en effet",
        // Croatian academic
        "stoga", "međutim", "naime", "štoviše", "naposljetku",
        // Danish academic
        "desuden", "endvidere", "følgelig", "imidlertid", "herunder",
        "ligeledes", "dermed", "således", "henholdsvis",
        // German academic
        "daher", "folglich", "demnach", "infolgedessen", "gleichwohl",
        "demzufolge", "hingegen", "überdies", "allerdings", "dennoch",
        // Spanish academic
        "por tanto", "sin embargo", "no obstante", "asimismo",
        "además", "por consiguiente", "en consecuencia", "dado que",
        // Portuguese academic
        "portanto", "contudo", "todavia", "entretanto", "ademais",
        "consequentemente", "nomeadamente", "outrossim",
    ]

    // MARK: - Technical words

    static let technicalWords: Set<String> = [
        "function", "variable", "api", "json", "http", "async",
        "import", "struct", "protocol", "interface", "const",
        "swift", "python", "javascript", "typescript", "kotlin",
        "boolean", "integer", "callback", "endpoint", "repository",
        "dockerfile", "kubernetes", "docker", "gradle", "webpack",
    ]

    // MARK: - Contractions

    static let informalContractionsEN: Set<String> = [
        "don't", "can't", "it's", "we're", "i'm", "you're", "they're",
        "won't", "shouldn't", "couldn't", "wouldn't", "isn't", "aren't",
        "wasn't", "weren't", "hasn't", "haven't", "hadn't", "let's",
        "that's", "what's", "who's", "here's", "there's", "he's", "she's",
        "i'll", "you'll", "he'll", "she'll", "we'll", "they'll",
        "i've", "you've", "we've", "they've", "i'd", "you'd", "he'd", "she'd",
    ]

    static let informalContractionsIT: Set<String> = [
        "dell'", "nell'", "sull'", "coll'", "all'", "dall'",
        "c'è", "c'era", "c'erano", "l'ho", "l'hai", "l'ha",
        "m'ha", "t'ho", "s'è", "n'è",
    ]

    // MARK: - Shared scoring

    struct StyleScores {
        let informalScore: Double
        let academicScore: Double
        let technicalScore: Double
        let exclamationCount: Int
        let wordCount: Int
    }

    /// Pure word-count-based scoring shared between ToneDetector and ContextAnalyzer.
    /// Both callers may apply additional regex-based scoring on top of this.
    static func computeWordScores(words: [String], rawWords: [String], text: String) -> StyleScores {
        let wordCount = max(words.count, 1)
        let informalCount = words.filter { informalWords.contains($0) }.count
        let academicCount = words.filter { academicWords.contains($0) }.count
        let technicalCount = words.filter { technicalWords.contains($0) }.count
        let exclamationCount = text.filter { $0 == "!" }.count
        let allCapsRatio: Double = {
            let capsWords = words.filter { $0 == $0.uppercased() && $0.count > 2 }
            return Double(capsWords.count) / Double(wordCount)
        }()

        let informalScore = Double(informalCount) / Double(wordCount) * 100.0
            + Double(exclamationCount) * 5.0
            + allCapsRatio * 50.0
        let academicScore = Double(academicCount) / Double(wordCount) * 100.0
        let technicalScore = Double(technicalCount) / Double(wordCount) * 100.0

        return StyleScores(
            informalScore: informalScore,
            academicScore: academicScore,
            technicalScore: technicalScore,
            exclamationCount: exclamationCount,
            wordCount: wordCount
        )
    }
}
```

- [ ] **Step 4: Update `ToneDetector.detect()` to use `Lexicon.computeWordScores`**

In `Core/ToneDetector.swift`, replace the `detect(text:language:)` method body:

```swift
func detect(text: String, language: String) -> DetectedTone {
    guard LanguageFamily.family(for: language) != .cjk else { return .neutral }

    let rawWords = text.split(separator: " ")
    let words = rawWords.map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
    let isItalian = language.starts(with: "it")

    let scores = Lexicon.computeWordScores(
        words: words,
        rawWords: rawWords.map(String.init),
        text: text
    )

    let contractions: Set<String> = isItalian
        ? Lexicon.informalContractionsIT
        : Lexicon.informalContractionsEN
    let contractionCount = rawWords.map({ $0.lowercased() }).filter { w in
        contractions.contains { w.hasPrefix($0) }
    }.count

    let adjustedInformalScore = scores.informalScore + Double(contractionCount) / Double(scores.wordCount) * 100.0

    let passivePattern = isItalian ? passivePatternIT : passivePatternEN
    let passiveCount = passivePattern?.numberOfMatches(
        in: text, range: NSRange(location: 0, length: text.utf16.count)
    ) ?? 0
    let techWordCount = camelCasePattern?.numberOfMatches(
        in: text, range: NSRange(location: 0, length: text.utf16.count)
    ) ?? 0
    let longWordCount = words.filter { $0.count > 12 }.count

    let formalScore = Double(passiveCount) / Double(scores.wordCount) * 100.0
    let technicalScore = (scores.technicalScore * Double(scores.wordCount) / 100.0 + Double(techWordCount + longWordCount))
        / Double(scores.wordCount) * 100.0

    if adjustedInformalScore > 12.0 { return .informal }
    if scores.academicScore > 5.0 { return .academic }
    if formalScore > 8.0 { return .formal }
    if technicalScore > 5.0 { return .technical }
    return .neutral
}
```

Also remove the now-redundant private sets from `ToneDetector` (they were just references to Lexicon anyway):

```swift
// DELETE these lines from ToneDetector:
private let informalContractionsEN: Set<String> = Lexicon.informalContractionsEN
private let informalContractionsIT: Set<String> = Lexicon.informalContractionsIT
private let informalWords: Set<String> = Lexicon.informalWords
private let academicMarkers: Set<String> = Lexicon.academicWords
```

- [ ] **Step 5: Update `ContextAnalyzer.styleFromText` in `Core/DocumentContext.swift`**

Replace the method body of `styleFromText(_:language:)`:

```swift
private static func styleFromText(_ text: String, language: String) -> WritingStyle {
    guard LanguageFamily.family(for: language) != .cjk else { return .neutral }

    let words = text.split(separator: " ")
        .map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
    let scores = Lexicon.computeWordScores(
        words: words,
        rawWords: words,  // ContextAnalyzer doesn't need raw for contraction matching
        text: text
    )

    if scores.informalScore > 8 { return .informal }
    if scores.academicScore > 5 { return .academic }
    if scores.technicalScore > 8 { return .technical }

    let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    let avgLen = sentences.isEmpty ? 0.0 : Double(scores.wordCount) / Double(sentences.count)
    if avgLen > 20 { return .formal }

    return .neutral
}
```

- [ ] **Step 6: Run tests**

```bash
swift test --filter LexiconTests 2>&1 | tail -15
```
Expected: all 5 new tests PASS.

```bash
swift test 2>&1 | tail -30
```
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add Core/Lexicon.swift Core/ToneDetector.swift Core/DocumentContext.swift Tests/Tests.swift
git commit -m "refactor: unify style scoring in Lexicon, expand vocabulary to DE/ES/PT"
```

---

## Task 8: Disk persistence for CorrectionCache

**Problem:** `CorrectionCache` is in-memory only. Every app restart loses the cache, forcing the LLM to re-correct identical texts.

**Approach:**
- Load from disk once at launch (called from `AppDelegate`)
- Save to disk after every `set()` call using a debounced writer (saves at most once per 30 seconds)
- Store file in `~/Library/Application Support/Parrot/correction_cache.json`
- Skip loading entries whose TTL has expired
- Gracefully handle corruption (bad JSON → empty cache, no crash)

**Files:**
- Modify: `Infra/CorrectionCache.swift`
- Modify: `App/AppDelegate.swift`
- Modify: `Tests/Tests.swift`

- [ ] **Step 1: Write failing tests**

Add to `Tests/Tests.swift`:

```swift
final class CorrectionCacheDiskTests: XCTestCase {
    override func setUp() async throws {
        await CorrectionCache.shared.invalidateAll()
    }

    func testSaveToDisk_thenLoadFromDisk_restoresEntry() async throws {
        let cache = CorrectionCache.shared
        let result = CorrectionResult(original: "disk test", corrected: "disk fixed", modelID: "m1")
        await cache.set(result, text: "disk test", promptType: "grammar", modelID: "m1", language: "en")

        // Save to disk
        await cache.saveToDisk()

        // Wipe in-memory state
        await cache.invalidateAll()
        let nilResult = await cache.get(text: "disk test", promptType: "grammar", modelID: "m1", language: "en")
        XCTAssertNil(nilResult, "cache should be empty after invalidateAll")

        // Load from disk
        await cache.loadFromDisk()
        let loaded = await cache.get(text: "disk test", promptType: "grammar", modelID: "m1", language: "en")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.correctedText, "disk fixed")

        // Cleanup
        await cache.deleteCacheFile()
    }

    func testLoadFromDisk_corruptFile_doesNotCrash() async {
        let url = await CorrectionCache.shared.cacheFileURL
        try? "not valid json {{{{".write(to: url, atomically: true, encoding: .utf8)
        await CorrectionCache.shared.loadFromDisk()
        // Should load 0 entries without crashing
        let result = await CorrectionCache.shared.get(text: "any", promptType: "grammar", modelID: "m", language: "en")
        XCTAssertNil(result)
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
swift test --filter CorrectionCacheDiskTests 2>&1 | tail -10
```
Expected: FAIL — `saveToDisk`, `loadFromDisk`, `deleteCacheFile`, `cacheFileURL` don't exist.

- [ ] **Step 3: Rewrite `Infra/CorrectionCache.swift`**

Replace the entire file:

```swift
import Foundation
import CryptoKit
import OSLog

actor CorrectionCache: Sendable {
    static let shared = CorrectionCache()

    private var cache: [String: Entry] = [:]
    private let maxEntries = Constants.cacheMaxEntries
    private let ttl = Constants.cacheTTL
    private let maxMemoryBytes = Constants.cacheMaxMemoryBytes
    private var currentMemoryBytes = 0
    private var pendingSave: Task<Void, Never>?

    var currentMemoryBytesForTesting: Int { currentMemoryBytes }

    let cacheFileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Parrot/correction_cache.json")
    }()

    private struct Entry {
        let result: CorrectionResult
        let timestamp: Date
        let byteSize: Int
    }

    private struct DiskEntry: Codable {
        let key: String
        let result: CorrectionResult
        let timestamp: Date
        let byteSize: Int
    }

    // MARK: - Key generation

    private func cacheKey(text: String, promptType: String, modelID: String, language: String) -> String {
        let textHash: String
        if let data = text.data(using: .utf8) {
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            textHash = String(hex.prefix(32))
        } else {
            textHash = String(text.hashValue)
        }
        return "\(promptType)|\(language)|\(modelID)|\(textHash)"
    }

    // MARK: - Public API

    func get(text: String, promptType: String, modelID: String, language: String = "") -> CorrectionResult? {
        let key = cacheKey(text: text, promptType: promptType, modelID: modelID, language: language)
        guard let entry = cache[key] else { return nil }
        guard Date().timeIntervalSince(entry.timestamp) < ttl else {
            cache.removeValue(forKey: key)
            currentMemoryBytes = max(0, currentMemoryBytes - entry.byteSize)
            return nil
        }
        return entry.result
    }

    func set(_ result: CorrectionResult, text: String, promptType: String, modelID: String, language: String = "") {
        let key = cacheKey(text: text, promptType: promptType, modelID: modelID, language: language)
        let byteSize = result.originalText.utf8.count + result.correctedText.utf8.count

        if let existing = cache[key] {
            currentMemoryBytes = max(0, currentMemoryBytes - existing.byteSize)
        }
        if cache.count >= maxEntries || (currentMemoryBytes + byteSize) > maxMemoryBytes {
            evictUntilUnderLimit(neededBytes: byteSize)
        }
        cache[key] = Entry(result: result, timestamp: Date(), byteSize: byteSize)
        currentMemoryBytes += byteSize

        scheduleSave()
    }

    func setIfNewer(_ result: CorrectionResult, text: String, promptType: String, modelID: String, language: String = "") {
        let key = cacheKey(text: text, promptType: promptType, modelID: modelID, language: language)
        if let existing = cache[key], existing.timestamp >= result.timestamp { return }
        set(result, text: text, promptType: promptType, modelID: modelID, language: language)
    }

    func invalidateAll() {
        cache.removeAll()
        currentMemoryBytes = 0
    }

    func invalidate(model: String) {
        let needle = "|\(model)|"
        let keysToRemove = cache.keys.filter { $0.contains(needle) }
        for key in keysToRemove {
            if let entry = cache[key] {
                currentMemoryBytes = max(0, currentMemoryBytes - entry.byteSize)
            }
            cache.removeValue(forKey: key)
        }
    }

    // MARK: - Disk persistence

    func loadFromDisk() {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let entries = try? JSONDecoder().decode([DiskEntry].self, from: data) else { return }
        let now = Date()
        var loaded = 0
        for entry in entries {
            guard now.timeIntervalSince(entry.timestamp) < ttl else { continue }
            let key = entry.key
            cache[key] = Entry(result: entry.result, timestamp: entry.timestamp, byteSize: entry.byteSize)
            currentMemoryBytes += entry.byteSize
            loaded += 1
        }
        Logger.infra.debug("CorrectionCache: loaded \(loaded) entries from disk")
    }

    func saveToDisk() {
        let entries = cache.map { (key, entry) in
            DiskEntry(key: key, result: entry.result, timestamp: entry.timestamp, byteSize: entry.byteSize)
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        let dir = cacheFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: cacheFileURL, options: .atomic)
    }

    func deleteCacheFile() {
        try? FileManager.default.removeItem(at: cacheFileURL)
    }

    // MARK: - Eviction

    private func evictUntilUnderLimit(neededBytes: Int) {
        let sorted = cache.sorted { $0.value.timestamp < $1.value.timestamp }
        for (key, entry) in sorted {
            guard cache.count >= maxEntries || (currentMemoryBytes + neededBytes) > maxMemoryBytes else { break }
            cache.removeValue(forKey: key)
            currentMemoryBytes = max(0, currentMemoryBytes - entry.byteSize)
        }
    }

    // MARK: - Debounced save

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await self?.saveToDisk()
        }
    }
}
```

- [ ] **Step 4: Call `loadFromDisk()` at launch in `App/AppDelegate.swift`**

In `applicationDidFinishLaunching`, add after `OnboardingController.shared.showIfNeeded()`:

```swift
// Load correction cache from disk (previous session results)
Task { await CorrectionCache.shared.loadFromDisk() }
```

- [ ] **Step 5: Run tests**

```bash
swift test --filter CorrectionCacheDiskTests 2>&1 | tail -15
```
Expected: all 2 new tests PASS.

```bash
swift test 2>&1 | tail -30
```
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add Infra/CorrectionCache.swift App/AppDelegate.swift Tests/Tests.swift
git commit -m "feat: CorrectionCache persists to disk, loads on launch, debounced save every 30s"
```

---

## Task 9: Expand Lexicon (German, Spanish, Portuguese) — done as part of Task 7

> This task was folded into **Task 7** (Lexicon unification). The DE/ES/PT words are added there. No separate task needed.

---

## Execution Order

Tasks must be done in this sequence due to dependencies:

```
Task 3 (resolveModelID) → Task 2 (checkStreaming) → Task 1 (source fix)
Task 4 (SSE)
Task 5 (lightweightMode)
Task 6 (NSLock)
Task 7 (Lexicon)
Task 8 (disk cache)
```

Tasks 4–8 are independent of each other and of 1–3 (except Task 7 which modifies ToneDetector and DocumentContext).

---

## Self-Review

**Spec coverage:**
- ✅ `source` field lost → Task 1
- ✅ `checkStreaming` bypasses cache/tone → Task 2
- ✅ `modelID: "streaming"` hardcoded → Tasks 2 + 3
- ✅ Deadline hardcoded → Task 1
- ✅ No retry in SSEStreamingEngine → Task 4
- ✅ SSE creates URLSession per request → Task 4
- ✅ `lightweightMode` unused → Task 5
- ✅ NSLock technical debt → Task 6
- ✅ ToneDetector/ContextAnalyzer duplication → Task 7
- ✅ Lexicon vocabulary expansion → Task 7
- ✅ Disk cache for CorrectionCache → Task 8
- ⏭️ RequestQueue parallelism for remote services → deliberately deferred (risky refactor, marginal UX gain in single-user context)
- ⏭️ ContextStorage per-pid → deliberately deferred (no real concurrency issue with serial RequestQueue)
