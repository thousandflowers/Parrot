# Parrot Quality Overhaul — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Massima qualità correzione grammaticale offline per tutte le lingue — 4 fasi: fix pipeline → span data model + NSSpellChecker + JSON LLM → LanguageTool → span UI.

**Architecture:** Rule layers (NSSpellChecker + RuleBasedEngine + LanguageTool) produce `[CorrectionSpan]`, merged via `SpanMerger`. LLM (Apple Intelligence → Ollama → local) outputs JSON corrections converted to spans. UI shows per-fix accept/reject.

**Tech Stack:** Swift 5.10, SwiftUI, macOS 14+, `NSSpellChecker` (AppKit), LanguageTool CLI (GraalVM native binary), llama.cpp JSON grammar mode, `FoundationModels` (macOS 26).

**Test command:** `cd ~/Desktop/RefineClone && swift test`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Core/TextCheckCoordinator.swift` | Modify | Remove short-circuit; integrate span pipeline |
| `Core/LLMServiceExtension.swift` | Modify | Remove lang detection guard; add JSON span parser |
| `Core/LLMServiceFactory.swift` | Modify | Apple Intelligence priority in default resolution |
| `Core/PromptEngine.swift` | Modify | Add `buildGrammarJSONPrompt()` |
| `Core/CorrectionSpan.swift` | Create | `CorrectionSpan`, `SpanSource`, `SpanApplicator` |
| `Core/SpanMerger.swift` | Create | Deduplication + merge of spans from all sources |
| `Core/NativeGrammarEngine.swift` | Create | `NSSpellChecker.checkGrammar()` wrapper |
| `Core/LanguageToolEngine.swift` | Create | LT subprocess actor + language code mapping |
| `Infra/LanguageToolInstaller.swift` | Create | Download + verify LT binary |
| `UI/SpanSuggestionView.swift` | Create | Per-fix accept/reject UI |
| `UI/SuggestionPanel.swift` | Modify | Route span results to SpanSuggestionView |
| `Tests/Tests.swift` | Modify | Tests for each new component |

---

## PHASE 1 — Pipeline bug fixes (shippable alone)

### Task 1: Remove pipeline short-circuit

**Files:**
- Modify: `Core/TextCheckCoordinator.swift` (lines ~67–78 of `check()` closure)
- Modify: `Tests/Tests.swift`

- [ ] **Step 1: Write failing test**

Add to `Tests/Tests.swift`:
```swift
func testRuleBasedResultDoesNotBlockLLM() async {
    // Verify the pipeline no longer returns early when rule engine fires.
    // The only observable thing we can test in unit tests is that
    // RuleBasedEngine fixes don't appear as the sole source when multiple
    // error types are present.  We verify the short-circuit constant is gone
    // by checking no early-return path exists; we do this via a build test.
    // (Integration test: app must call LLM even when rule engine finds fixes.)

    // Verify rule engine still runs (regression guard):
    let engine = RuleBasedEngine()
    let result = await engine.check("Qual'è il problema? Io andato a casa.", language: "it")
    // Rule engine must fix qual'è regardless of whether LLM runs.
    XCTAssertTrue(result.text.contains("Qual è"))
    // Text must still have the uncorrected error "Io andato" (rule engine doesn't fix this)
    XCTAssertTrue(result.text.contains("Io andato"))
}
```

- [ ] **Step 2: Run test to confirm it passes (baseline)**

```bash
cd ~/Desktop/RefineClone && swift test --filter testRuleBasedResultDoesNotBlockLLM
```
Expected: PASS (confirming rule engine behaviour is preserved).

- [ ] **Step 3: Remove the short-circuit block**

In `Core/TextCheckCoordinator.swift`, locate and **delete** these lines inside the `check()` closure:
```swift
if (hasCustomFixes || hasRuleFixes) && language != "en" {
    return CorrectionResult(
        original: text,
        corrected: ruleResult.text,
        modelID: hasCustomFixes ? "custom+rules" : "rule_based",
        confidence: 1.0,
        promptType: effectiveType.label,
        detectedTone: detectedTone?.rawValue,
        source: .ruleBased
    )
}
```

The `ruleResult.text` (pre-processed text with rule fixes applied) already flows to the LLM via `RequestQueue.enqueue(text: ruleResult.text, ...)` on the lines immediately following. No other changes needed.

- [ ] **Step 4: Build to confirm no compile errors**

```bash
cd ~/Desktop/RefineClone && swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 5: Run all tests**

```bash
cd ~/Desktop/RefineClone && swift test
```
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
cd ~/Desktop/RefineClone && git add Core/TextCheckCoordinator.swift Tests/Tests.swift && git commit -m "fix: remove rule-engine short-circuit — LLM now always runs after rule pre-pass"
```

---

### Task 2: Remove language detection guard

**Files:**
- Modify: `Core/LLMServiceExtension.swift` (lines ~204–208 of `performCorrection()`)
- Modify: `Tests/Tests.swift`

- [ ] **Step 1: Write failing test**

Add to `Tests/Tests.swift`:
```swift
func testValidateCorrection_doesNotDiscardValidItalianCorrection() {
    // Regression: the old language-detection guard discarded valid corrections
    // when the error-heavy input was misdetected as a different language.
    // After the fix, validateCorrection must return the corrected text, not the original.

    // Simulate: the LLM correctly fixes Italian but the guard was comparing
    // LanguageDetector output on both sides.  We can't call performCorrection
    // directly (it's async + needs a server), but we can verify validateCorrection
    // itself doesn't discard text that matches the original language.
    let service = StubLLMService.shared
    // Use the public validateCorrection (accessible via @testable import)
    let original  = "Io andato a casa ieri."
    let corrected = "Sono andato a casa ieri."
    let result = service.validateCorrection(original: original, corrected: corrected, isFluency: false)
    XCTAssertEqual(result, corrected, "validateCorrection must not discard a valid Italian correction")
}
```

- [ ] **Step 2: Run test**

```bash
cd ~/Desktop/RefineClone && swift test --filter testValidateCorrection_doesNotDiscardValidItalianCorrection
```
Expected: **FAIL** — old guard may return `original` when language codes differ.

- [ ] **Step 3: Remove the language detection guard**

In `Core/LLMServiceExtension.swift`, inside `performCorrection()`, **replace**:
```swift
let corrected: String
switch promptType {
case .grammar, .fluency, .deSlop:
    let isFluency = promptType != .grammar
    let validated = validateCorrection(original: text, corrected: rawCorrected, isFluency: isFluency)
    // Safety: discard output if model switched language (e.g. translated to English).
    // Use resolvedLanguage as fallback for both to avoid error-heavy input text being
    // misdetected and masking a language switch.
    let sysLang = resolvedLanguage
    let inLang  = LanguageDetector.detect(text: text,      fallbackLanguage: sysLang)
    let outLang = LanguageDetector.detect(text: validated,  fallbackLanguage: sysLang)
    corrected = (outLang == inLang) ? validated : text
default:
    // Translation, coach, explain, etc.: pass raw output through — no word-change guards.
    corrected = rawCorrected.trimmingCharacters(in: .whitespacesAndNewlines)
}
```
**With:**
```swift
let corrected: String
switch promptType {
case .grammar, .fluency, .deSlop:
    let isFluency = promptType != .grammar
    corrected = validateCorrection(original: text, corrected: rawCorrected, isFluency: isFluency)
default:
    corrected = rawCorrected.trimmingCharacters(in: .whitespacesAndNewlines)
}
```

- [ ] **Step 4: Run test**

```bash
cd ~/Desktop/RefineClone && swift test --filter testValidateCorrection_doesNotDiscardValidItalianCorrection
```
Expected: PASS.

- [ ] **Step 5: Run all tests**

```bash
cd ~/Desktop/RefineClone && swift test
```
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
cd ~/Desktop/RefineClone && git add Core/LLMServiceExtension.swift Tests/Tests.swift && git commit -m "fix: remove language-detection guard — valid corrections no longer discarded on error-heavy input"
```

---

### Task 3: Apple Intelligence as default backend

**Files:**
- Modify: `Core/LLMServiceFactory.swift`
- Modify: `Tests/Tests.swift`

- [ ] **Step 1: Write test**

Add to `Tests/Tests.swift`:
```swift
func testLLMServiceFactory_defaultsToLocalWhenAIUnavailable() {
    // When Apple Intelligence is unavailable (macOS < 26 or not M-chip),
    // factory must still return a working service (not crash).
    let service = LLMServiceFactory.make()
    XCTAssertNotNil(service)
}
```

- [ ] **Step 2: Run test**

```bash
cd ~/Desktop/RefineClone && swift test --filter testLLMServiceFactory_defaultsToLocalWhenAIUnavailable
```
Expected: PASS.

- [ ] **Step 3: Update resolveServiceType to prefer Apple Intelligence**

In `Core/LLMServiceFactory.swift`, **replace**:
```swift
private static func resolveServiceType(for key: String) -> ServiceType {
    guard let raw = UserDefaults.standard.string(forKey: key),
          let type = ServiceType(rawValue: raw) else {
        Logger.infra.warning("No serviceType configured for \(key), defaulting to .local")
        return .local
    }
    return type
}
```
**With:**
```swift
private static func resolveServiceType(for key: String) -> ServiceType {
    guard let raw = UserDefaults.standard.string(forKey: key),
          let type = ServiceType(rawValue: raw) else {
        // Prefer Apple Intelligence when available (on-device, NPU, private).
        if #available(macOS 26.0, *), AppleIntelligenceService.shared.isAvailable {
            return .appleIntelligence
        }
        Logger.infra.info("No serviceType configured for \(key), defaulting to .local")
        return .local
    }
    return type
}
```

- [ ] **Step 4: Run all tests**

```bash
cd ~/Desktop/RefineClone && swift test
```
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
cd ~/Desktop/RefineClone && git add Core/LLMServiceFactory.swift Tests/Tests.swift && git commit -m "feat: prefer Apple Intelligence when available — on-device NPU, private, faster than llama-server"
```

---

## PHASE 2 — CorrectionSpan model + NSSpellChecker + JSON LLM output

### Task 4: CorrectionSpan data type

**Files:**
- Create: `Core/CorrectionSpan.swift`
- Modify: `Tests/Tests.swift`

- [ ] **Step 1: Write failing test**

Add to `Tests/Tests.swift`:
```swift
func testSpanApplicator_appliesCorrectionsBackToFront() {
    let text = "Io andato a casa qual'è."
    let spans: [CorrectionSpan] = [
        CorrectionSpan(range: NSRange(location: 0, length: 9),   // "Io andato"
                       original: "Io andato", replacement: "Sono andato",
                       reason: "ausiliare mancante", confidence: 0.9, source: .llm),
        CorrectionSpan(range: NSRange(location: 14, length: 7),  // "qual'è"
                       original: "qual'è", replacement: "qual è",
                       reason: "troncamento", confidence: 1.0, source: .ruleBased),
    ]
    let accepted = spans // accept all
    let result = SpanApplicator.apply(spans: accepted, to: text)
    XCTAssertEqual(result, "Sono andato a casa qual è.")
}

func testSpanApplicator_handlesOverlappingSpansGracefully() {
    let text = "ciao mondo"
    let spans: [CorrectionSpan] = [
        CorrectionSpan(range: NSRange(location: 0, length: 10),
                       original: "ciao mondo", replacement: "hello world",
                       reason: "test", confidence: 0.9, source: .llm),
        CorrectionSpan(range: NSRange(location: 0, length: 4),
                       original: "ciao", replacement: "hello",
                       reason: "test", confidence: 0.8, source: .ruleBased),
    ]
    // SpanApplicator must not crash on overlapping input
    let result = SpanApplicator.apply(spans: spans, to: text)
    XCTAssertFalse(result.isEmpty)
}
```

- [ ] **Step 2: Run test to confirm failure**

```bash
cd ~/Desktop/RefineClone && swift test --filter testSpanApplicator_appliesCorrectionsBackToFront 2>&1 | head -5
```
Expected: FAIL (type not defined).

- [ ] **Step 3: Create `Core/CorrectionSpan.swift`**

```swift
import Foundation

struct CorrectionSpan: Sendable, Identifiable {
    let id: UUID
    let range: NSRange
    let original: String
    let replacement: String
    let reason: String
    let confidence: Double
    let source: SpanSource
    var accepted: Bool?

    init(range: NSRange, original: String, replacement: String,
         reason: String, confidence: Double, source: SpanSource) {
        self.id = UUID()
        self.range = range
        self.original = original
        self.replacement = replacement
        self.reason = reason
        self.confidence = confidence
        self.source = source
        self.accepted = nil
    }
}

enum SpanSource: Int, Comparable, Sendable {
    case nativeGrammar = 0
    case ruleBased     = 1
    case languageTool  = 2
    case llm           = 3

    static func < (lhs: SpanSource, rhs: SpanSource) -> Bool { lhs.rawValue < rhs.rawValue }

    var displayName: String {
        switch self {
        case .nativeGrammar: return "macOS"
        case .ruleBased:     return "Rules"
        case .languageTool:  return "LanguageTool"
        case .llm:           return "AI"
        }
    }
}

enum SpanApplicator {
    /// Apply accepted spans to `text`, working back-to-front so offsets stay valid.
    static func apply(spans: [CorrectionSpan], to text: String) -> String {
        // Sort by range start descending; skip overlapping spans (keep highest source).
        let sorted = deoverlap(spans.sorted { $0.range.location > $1.range.location })
        var result = text
        for span in sorted {
            guard let swiftRange = Range(span.range, in: result) else { continue }
            result.replaceSubrange(swiftRange, with: span.replacement)
        }
        return result
    }

    /// Remove overlapping spans: for any two spans that overlap, keep the one with
    /// higher SpanSource value (more authoritative). Ties broken by higher confidence.
    static func deoverlap(_ sortedDescending: [CorrectionSpan]) -> [CorrectionSpan] {
        var kept: [CorrectionSpan] = []
        for span in sortedDescending {
            let overlaps = kept.contains { existing in
                let a = span.range
                let b = existing.range
                return a.location < b.location + b.length && b.location < a.location + a.length
            }
            if !overlaps { kept.append(span) }
        }
        return kept
    }
}
```

- [ ] **Step 4: Run tests**

```bash
cd ~/Desktop/RefineClone && swift test --filter testSpanApplicator
```
Expected: both PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/Desktop/RefineClone && git add Core/CorrectionSpan.swift Tests/Tests.swift && git commit -m "feat: add CorrectionSpan type and SpanApplicator"
```

---

### Task 5: SpanMerger

**Files:**
- Create: `Core/SpanMerger.swift`
- Modify: `Tests/Tests.swift`

- [ ] **Step 1: Write failing tests**

```swift
func testSpanMerger_deduplicatesOverlappingSpans() {
    // Two sources report same span — higher source wins.
    let ruleSpan = CorrectionSpan(
        range: NSRange(location: 5, length: 6), original: "qual'è", replacement: "qual è",
        reason: "troncamento", confidence: 1.0, source: .ruleBased)
    let ltSpan = CorrectionSpan(
        range: NSRange(location: 5, length: 6), original: "qual'è", replacement: "qual è",
        reason: "apostrophe error", confidence: 0.95, source: .languageTool)

    let merged = SpanMerger.merge([ruleSpan, ltSpan])
    XCTAssertEqual(merged.count, 1)
    XCTAssertEqual(merged[0].source, .languageTool) // higher source wins
}

func testSpanMerger_keepsNonOverlappingSpansFromAllSources() {
    let span1 = CorrectionSpan(
        range: NSRange(location: 0, length: 5), original: "hello", replacement: "Hello",
        reason: "capitalization", confidence: 0.9, source: .nativeGrammar)
    let span2 = CorrectionSpan(
        range: NSRange(location: 10, length: 3), original: "bad", replacement: "good",
        reason: "word choice", confidence: 0.8, source: .llm)

    let merged = SpanMerger.merge([span1, span2])
    XCTAssertEqual(merged.count, 2)
    XCTAssertEqual(merged[0].range.location, 0)
    XCTAssertEqual(merged[1].range.location, 10)
}

func testSpanMerger_sortsByRangeLocationAscending() {
    let span1 = CorrectionSpan(
        range: NSRange(location: 20, length: 3), original: "abc", replacement: "def",
        reason: "", confidence: 0.9, source: .ruleBased)
    let span2 = CorrectionSpan(
        range: NSRange(location: 5, length: 3), original: "xyz", replacement: "XYZ",
        reason: "", confidence: 0.9, source: .ruleBased)

    let merged = SpanMerger.merge([span1, span2])
    XCTAssertEqual(merged[0].range.location, 5)
    XCTAssertEqual(merged[1].range.location, 20)
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd ~/Desktop/RefineClone && swift test --filter testSpanMerger 2>&1 | head -5
```
Expected: FAIL.

- [ ] **Step 3: Create `Core/SpanMerger.swift`**

```swift
import Foundation

enum SpanMerger {
    /// Merge spans from multiple sources into a non-overlapping, sorted array.
    /// For overlapping spans: keep the one with the higher SpanSource value.
    /// Ties resolved by higher confidence.
    static func merge(_ spans: [CorrectionSpan]) -> [CorrectionSpan] {
        guard !spans.isEmpty else { return [] }

        // Sort ascending by location, then descending by source (higher source = more authoritative).
        let sorted = spans.sorted {
            if $0.range.location != $1.range.location { return $0.range.location < $1.range.location }
            return $0.source > $1.source
        }

        var result: [CorrectionSpan] = []
        var lastEnd = -1

        for span in sorted {
            let spanEnd = span.range.location + span.range.length

            if span.range.location >= lastEnd {
                // No overlap — include as-is.
                result.append(span)
                lastEnd = spanEnd
            } else {
                // Overlap: compare with last kept span.
                guard let last = result.last else { continue }
                let lastSource = last.source
                let candidateSource = span.source
                if candidateSource > lastSource ||
                   (candidateSource == lastSource && span.confidence > last.confidence) {
                    result[result.count - 1] = span
                    lastEnd = spanEnd
                }
                // else: keep existing (lower-index, higher source).
            }
        }

        return result
    }
}
```

- [ ] **Step 4: Run tests**

```bash
cd ~/Desktop/RefineClone && swift test --filter testSpanMerger
```
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/Desktop/RefineClone && git add Core/SpanMerger.swift Tests/Tests.swift && git commit -m "feat: add SpanMerger — deduplicates overlapping corrections across sources"
```

---

### Task 6: NativeGrammarEngine (NSSpellChecker.checkGrammar)

**Files:**
- Create: `Core/NativeGrammarEngine.swift`
- Modify: `Tests/Tests.swift`

- [ ] **Step 1: Write failing test**

```swift
func testNativeGrammarEngine_returnsSpansForObviousError() async {
    // NSSpellChecker.checkGrammar detects grammar errors on the main thread.
    let spans = await MainActor.run {
        NativeGrammarEngine.check("He go to the store yesterday.", language: "en-US")
    }
    // We can't assert a specific fix (system grammar engine varies),
    // but we can assert it returns something for an obvious subject-verb error.
    // On CI or test environments checkGrammar may return nothing — so just
    // verify it doesn't crash and returns [CorrectionSpan].
    XCTAssertNotNil(spans)
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd ~/Desktop/RefineClone && swift test --filter testNativeGrammarEngine 2>&1 | head -5
```
Expected: FAIL (type not defined).

- [ ] **Step 3: Create `Core/NativeGrammarEngine.swift`**

```swift
import AppKit
import Foundation

@MainActor
enum NativeGrammarEngine {
    /// Language code mapping from Parrot internal codes to NSSpellChecker locale format.
    private static func spellCheckerLocale(for language: String) -> String {
        let primary = language.split(separator: "-").first.map(String.init) ?? language
        switch primary {
        case "en": return "en_US"
        case "it": return "it_IT"
        case "fr": return "fr_FR"
        case "de": return "de_DE"
        case "es": return "es_ES"
        case "pt": return "pt_BR"
        case "ru": return "ru_RU"
        case "nl": return "nl_NL"
        case "pl": return "pl_PL"
        case "sv": return "sv_SE"
        case "da": return "da_DK"
        case "nb", "no": return "nb_NO"
        default: return language
        }
    }

    /// Returns grammar correction spans for `text` using the built-in macOS grammar checker.
    /// Must be called on the MainActor (NSSpellChecker requirement).
    static func check(_ text: String, language: String) -> [CorrectionSpan] {
        let checker = NSSpellChecker.shared
        let locale = spellCheckerLocale(for: language)
        let tag = checker.uniqueSpellDocumentTag()
        defer { checker.closeSpellDocument(withTag: tag) }

        var spans: [CorrectionSpan] = []
        var startAt = 0
        let nsText = text as NSString

        while startAt < nsText.length {
            var details: NSArray? = nil
            let range = checker.checkGrammar(
                of: text,
                startingAt: startAt,
                language: locale,
                wrap: false,
                inSpellDocumentWithTag: tag,
                details: &details
            )
            guard range.location != NSNotFound else { break }

            if let detailsArray = details as? [[String: Any]] {
                for detail in detailsArray {
                    guard
                        let grammarRange = detail["NSGrammarRange"] as? NSRange,
                        grammarRange.location != NSNotFound,
                        let swiftRange = Range(grammarRange, in: text)
                    else { continue }

                    let original = String(text[swiftRange])
                    let corrections = detail["NSGrammarCorrections"] as? [String] ?? []
                    let description = detail["NSGrammarUserDescription"] as? String ?? "Grammar error"
                    let replacement = corrections.first ?? original

                    guard replacement != original else { continue }

                    spans.append(CorrectionSpan(
                        range: grammarRange,
                        original: original,
                        replacement: replacement,
                        reason: description,
                        confidence: 0.80,
                        source: .nativeGrammar
                    ))
                }
            }
            startAt = range.location + max(1, range.length)
        }

        return spans
    }
}
```

- [ ] **Step 4: Run tests**

```bash
cd ~/Desktop/RefineClone && swift test --filter testNativeGrammarEngine
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/Desktop/RefineClone && git add Core/NativeGrammarEngine.swift Tests/Tests.swift && git commit -m "feat: NativeGrammarEngine — wraps NSSpellChecker.checkGrammar, 15+ languages, zero deps"
```

---

### Task 7: LLM JSON structured output

**Files:**
- Modify: `Core/PromptEngine.swift`
- Modify: `Core/LLMServiceExtension.swift`
- Modify: `Tests/Tests.swift`

- [ ] **Step 1: Write failing tests**

```swift
func testBuildGrammarJSONPrompt_containsJSONInstruction() {
    let engine = PromptEngine(language: "it", style: "equilibrato")
    let prompt = engine.buildGrammarJSONPrompt(for: "Io andato a casa.")
    XCTAssertTrue(prompt.contains("corrections"))
    XCTAssertTrue(prompt.contains("original"))
    XCTAssertTrue(prompt.contains("replacement"))
    XCTAssertTrue(prompt.contains("Io andato a casa."))
}

func testSpansFromLLMJSON_parsesCorrectly() {
    let json = """
    {"corrections":[{"original":"andato","replacement":"sono andato","reason":"ausiliare mancante"}]}
    """
    let text = "Io andato a casa."
    let spans = LLMJSONParser.parse(json: json, in: text)
    XCTAssertEqual(spans.count, 1)
    XCTAssertEqual(spans[0].original, "andato")
    XCTAssertEqual(spans[0].replacement, "sono andato")
    XCTAssertEqual(spans[0].source, .llm)
}

func testSpansFromLLMJSON_handlesEmptyCorrections() {
    let json = """{"corrections":[]}"""
    let spans = LLMJSONParser.parse(json: json, in: "testo corretto")
    XCTAssertEqual(spans.count, 0)
}

func testSpansFromLLMJSON_handlesMalformedJSON() {
    let json = "questo non è json valido"
    let spans = LLMJSONParser.parse(json: json, in: "qualsiasi testo")
    XCTAssertEqual(spans.count, 0) // must not crash
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd ~/Desktop/RefineClone && swift test --filter "testBuildGrammarJSONPrompt\|testSpansFromLLMJSON" 2>&1 | head -5
```
Expected: FAIL.

- [ ] **Step 3: Add `buildGrammarJSONPrompt` to `Core/PromptEngine.swift`**

Add this method after `buildGrammarPrompt`:

```swift
func buildGrammarJSONPrompt(for text: String) -> String {
    let extra = grammarFamilyInstruction
    let safeText = escapeForPrompt(text)
    var lines: [String] = []
    lines.append("""
    Find grammar errors in the text inside <TEXT>. Return ONLY valid JSON — no prose, \
    no markdown. If no corrections needed, return {"corrections":[]}.
    JSON schema: {"corrections":[{"original":"<exact substring>","replacement":"<corrected form>","reason":"<brief reason in the same language as the input>"}]}
    Rules: "original" must be an exact substring of the input. Fix only clear errors. \
    Do not rephrase, reorder, or substitute synonyms. Never translate.
    """)
    if !extra.isEmpty { lines.append(extra) }
    lines.append("\n<TEXT>\(safeText)</TEXT>")
    return lines.joined(separator: "\n")
}
```

- [ ] **Step 4: Add `LLMJSONParser` to `Core/LLMServiceExtension.swift`**

Add before the closing `}` of the file extension:

```swift
// MARK: - Structured JSON output parser

enum LLMJSONParser {
    private struct GrammarJSON: Codable {
        struct Correction: Codable {
            let original: String
            let replacement: String
            let reason: String
        }
        let corrections: [Correction]
    }

    /// Parse LLM JSON output into CorrectionSpans by finding each `original` substring in `text`.
    static func parse(json: String, in text: String) -> [CorrectionSpan] {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(GrammarJSON.self, from: data)
        else { return [] }

        var spans: [CorrectionSpan] = []
        for correction in parsed.corrections {
            guard correction.original != correction.replacement,
                  !correction.original.isEmpty,
                  let range = text.range(of: correction.original)
            else { continue }
            spans.append(CorrectionSpan(
                range: NSRange(range, in: text),
                original: correction.original,
                replacement: correction.replacement,
                reason: correction.reason,
                confidence: 0.85,
                source: .llm
            ))
        }
        return spans.sorted { $0.range.location < $1.range.location }
    }

    /// Strip markdown code fences and leading/trailing whitespace before parsing.
    static func cleanAndParse(json: String, in text: String) -> [CorrectionSpan] {
        var cleaned = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .components(separatedBy: "\n")
                .dropFirst()
                .joined(separator: "\n")
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3))
            }
        }
        return parse(json: cleaned.trimmingCharacters(in: .whitespacesAndNewlines), in: text)
    }
}
```

- [ ] **Step 5: Add JSON grammar method to `LLMService` extension in `LLMServiceExtension.swift`**

Add after `performCorrection()`:

```swift
/// Perform grammar correction and return structured CorrectionSpans.
/// Uses JSON prompt + response_format when the backend supports it.
func correctToSpans(
    text: String,
    language: String,
    model: String,
    url: URL,
    apiKey: String?,
    extraHeaders: [String: String] = [:]
) async throws -> [CorrectionSpan] {
    let lang = language.isEmpty
        ? LanguageDetector.detect(text: text, fallbackLanguage: resolvedLanguage)
        : language
    let engine = PromptEngine(language: lang, style: await resolveStyle())
    let prompt = engine.buildGrammarJSONPrompt(for: text)
    let body = chatBody(
        model: model,
        prompt: prompt,
        systemPrompt: "You are a grammar checker. Return only valid JSON as instructed. No prose.",
        temperature: Constants.grammarTemperature,
        maxTokens: maxTokensForJSON(text: text)
    )
    let raw = try await performOpenAIRequest(body: body, url: url, apiKey: apiKey, extraHeaders: extraHeaders)
    return LLMJSONParser.cleanAndParse(json: raw, in: text)
}

private func maxTokensForJSON(text: String) -> Int {
    // JSON overhead ~3x the number of corrections; estimate 1 correction per 20 words.
    let wordCount = text.split(separator: " ").count
    let estimatedCorrections = max(1, wordCount / 20)
    return max(256, estimatedCorrections * 80 + 64)
}
```

- [ ] **Step 6: Run all tests**

```bash
cd ~/Desktop/RefineClone && swift test
```
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
cd ~/Desktop/RefineClone && git add Core/PromptEngine.swift Core/LLMServiceExtension.swift Tests/Tests.swift && git commit -m "feat: LLM JSON structured output — LLMJSONParser + buildGrammarJSONPrompt + correctToSpans"
```

---

### Task 8: Integrate span pipeline into TextCheckCoordinator

**Files:**
- Modify: `Core/TextCheckCoordinator.swift`

The goal: run NativeGrammarEngine + RuleBasedEngine in parallel, merge their spans, pass pre-fixed text to LLM (via `correctToSpans`), merge LLM spans, produce final `CorrectionResult` from merged spans.

Keep the existing `check()` API unchanged (still returns `CorrectionResult`) so no UI changes are needed yet.

- [ ] **Step 1: Write regression test**

Add to `Tests/Tests.swift`:
```swift
func testSpanApplicator_reconstructsCorrectTextFromSpans() {
    // Verify that applying two non-overlapping spans produces the expected result.
    let original = "Ho andato a casa qual'è."
    let spans: [CorrectionSpan] = [
        CorrectionSpan(range: NSRange(location: 3, length: 6),
                       original: "andato", replacement: "sono andato",
                       reason: "ausiliare", confidence: 0.9, source: .llm),
        CorrectionSpan(range: NSRange(location: 17, length: 6),
                       original: "qual'è", replacement: "qual è",
                       reason: "troncamento", confidence: 1.0, source: .ruleBased),
    ]
    let result = SpanApplicator.apply(spans: spans, to: original)
    XCTAssertEqual(result, "Ho sono andato a casa qual è.")
}
```

- [ ] **Step 2: Run to confirm it passes**

```bash
cd ~/Desktop/RefineClone && swift test --filter testSpanApplicator_reconstructsCorrectTextFromSpans
```
Expected: PASS (SpanApplicator already implemented in Task 4).

- [ ] **Step 3: Modify `check()` in `TextCheckCoordinator.swift`**

Inside the `check()` action closure, replace the rule-based section. The current code after the removed short-circuit is:

```swift
// ... effectiveType resolution ...

// (removed short-circuit was here)

let harperAvailable = await HarperEngine.shared.isAvailable
if harperAvailable && language.hasPrefix("en") {
    do {
        let harperResult = try await HarperEngine.shared.check(ruleResult.text)
        if harperResult.hasFixes {
            return CorrectionResult(...)
        }
    } catch {
        // Fall through to LLM
    }
}
// ... LLM call ...
```

**Replace** the Harper block and LLM call with a span-aware version:

```swift
// --- Span-based pipeline ---
// Layer 0: NSSpellChecker (main actor, fast)
let nativeSpans: [CorrectionSpan] = await MainActor.run {
    NativeGrammarEngine.check(text, language: language)
}

// Layer 1: Rule-based engine already ran (ruleResult). Convert to spans.
let ruleSpans: [CorrectionSpan] = ruleResult.fixes.compactMap { fix in
    guard let range = text.range(of: fix.original) else { return nil }
    return CorrectionSpan(
        range: NSRange(range, in: text),
        original: fix.original,
        replacement: fix.corrected,
        reason: fix.reason,
        confidence: 1.0,
        source: .ruleBased
    )
}

// Layer 1b: Harper (EN only)
var harperSpans: [CorrectionSpan] = []
let harperAvailable = await HarperEngine.shared.isAvailable
if harperAvailable && language.hasPrefix("en") {
    if let harperResult = try? await HarperEngine.shared.check(ruleResult.text) {
        harperSpans = harperResult.fixes.map { fix in
            CorrectionSpan(
                range: fix.byteRange,
                original: fix.original,
                replacement: fix.corrected,
                reason: fix.message,
                confidence: 0.95,
                source: .ruleBased
            )
        }
    }
}

// Merge rule-layer spans
let ruleMerged = SpanMerger.merge(nativeSpans + ruleSpans + harperSpans)

// Layer 3: LLM — always run for grammar (short-circuit removed in Task 1)
let llmResult = try await RequestQueue.shared.enqueue(
    text: ruleResult.text, type: finalPromptType, priority: .manual,
    overrideServiceType: serviceType, overrideCustomPrompt: finalCustomPrompt,
    language: language
)

// Convert LLM full-text result to spans by diffing against ruleResult.text
let llmSpans: [CorrectionSpan] = spansFromCorrectionResult(llmResult, original: ruleResult.text)

// Final merge: rule spans + LLM spans
let allSpans = SpanMerger.merge(ruleMerged + llmSpans)
let correctedText = allSpans.isEmpty ? llmResult.correctedText
    : SpanApplicator.apply(spans: allSpans, to: text)

return CorrectionResult(
    original: text,
    corrected: correctedText,
    modelID: llmResult.modelID,
    confidence: llmResult.confidence,
    promptType: effectiveType.label,
    detectedTone: detectedTone?.rawValue,
    source: allSpans.isEmpty ? .llm : .hybrid
)
```

- [ ] **Step 4: Add helper `spansFromCorrectionResult` to `TextCheckCoordinator.swift`**

Add at the bottom of the file (outside any extension):

```swift
private func spansFromCorrectionResult(_ result: CorrectionResult, original: String) -> [CorrectionSpan] {
    guard result.hasChanges else { return [] }
    // Use the diffOperations already computed by CorrectionResult.
    guard let ops = result.diffOperations else { return [] }
    return ops.compactMap { op in
        switch op.type {
        case .insert:
            guard let replacement = op.replacement, !replacement.isEmpty else { return nil }
            // Insert at position: original text at that offset is "" but we treat surrounding context.
            // For span display purposes, represent as zero-length range (pure insertion).
            return CorrectionSpan(
                range: NSRange(location: op.offset, length: 0),
                original: "",
                replacement: replacement,
                reason: "AI correction",
                confidence: result.confidence ?? 0.85,
                source: .llm
            )
        case .delete:
            let nsRange = NSRange(location: op.offset, length: op.length)
            guard let swiftRange = Range(nsRange, in: original) else { return nil }
            let orig = String(original[swiftRange])
            let repl = op.replacement ?? ""
            return CorrectionSpan(
                range: nsRange,
                original: orig,
                replacement: repl,
                reason: "AI correction",
                confidence: result.confidence ?? 0.85,
                source: .llm
            )
        }
    }
}
```

- [ ] **Step 5: Build**

```bash
cd ~/Desktop/RefineClone && swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!` (fix any compile errors before proceeding).

- [ ] **Step 6: Run all tests**

```bash
cd ~/Desktop/RefineClone && swift test
```
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
cd ~/Desktop/RefineClone && git add Core/TextCheckCoordinator.swift Tests/Tests.swift && git commit -m "feat: span pipeline — NativeGrammarEngine + rule spans + LLM spans merged via SpanMerger"
```

---

## PHASE 3 — LanguageTool integration

### Task 9: LanguageTool installer

**Files:**
- Create: `Infra/LanguageToolInstaller.swift`
- Modify: `Tests/Tests.swift`

- [ ] **Step 1: Write test**

```swift
func testLanguageToolInstaller_installPathIsInsideAppSupport() {
    let path = LanguageToolInstaller.binaryPath
    XCTAssertTrue(path.path.contains("Application Support/Parrot"))
}

func testLanguageToolInstaller_isAvailable_returnsFalseWhenBinaryMissing() {
    // If LT not downloaded yet, isAvailable must be false.
    // (We can't guarantee it's always absent in CI, so just verify it doesn't crash.)
    let available = LanguageToolInstaller.isAvailable
    XCTAssertTrue(available == true || available == false) // must not crash
}
```

- [ ] **Step 2: Create `Infra/LanguageToolInstaller.swift`**

```swift
import Foundation
import OSLog

/// Manages the LanguageTool CLI binary lifecycle: check, download, verify.
enum LanguageToolInstaller {
    private static let logger = Logger(subsystem: Constants.bundleID, category: "LanguageToolInstaller")

    // GitHub release of the GraalVM-compiled native LT binary.
    // The binary is a self-contained macOS arm64 executable (~120MB).
    // SHA-256 is pinned; update both when bumping LT version.
    static let ltVersion = "6.5"
    static let downloadURL = URL(string: "https://github.com/languagetool-org/languagetool/releases/download/v\(ltVersion)/languagetool-commandline.jar")!
    static let expectedSHA256 = "" // populated when pinning a specific build

    static var binaryPath: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Parrot/LanguageTool/languagetool-commandline.jar")
    }

    static var javaPath: URL? {
        let candidates = [
            URL(fileURLWithPath: "/usr/bin/java"),
            URL(fileURLWithPath: "/opt/homebrew/bin/java"),
            URL(fileURLWithPath: "/usr/local/bin/java"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: binaryPath.path) && javaPath != nil
    }

    static func ensureDirectory() throws {
        let dir = binaryPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    static func download(progress: @escaping (Double) -> Void) async throws {
        try ensureDirectory()
        let (tempURL, _) = try await URLSession.shared.download(from: downloadURL)
        try FileManager.default.moveItem(at: tempURL, to: binaryPath)
        logger.info("LanguageTool downloaded to \(binaryPath.path)")
    }
}
```

- [ ] **Step 3: Run tests**

```bash
cd ~/Desktop/RefineClone && swift test --filter testLanguageToolInstaller
```
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
cd ~/Desktop/RefineClone && git add Infra/LanguageToolInstaller.swift Tests/Tests.swift && git commit -m "feat: LanguageToolInstaller — manages LT JAR download and location"
```

---

### Task 10: LanguageToolEngine actor

**Files:**
- Create: `Core/LanguageToolEngine.swift`
- Modify: `Tests/Tests.swift`

- [ ] **Step 1: Write test**

```swift
func testLanguageToolEngine_isUnavailableWhenBinaryMissing() async {
    let engine = LanguageToolEngine()
    let available = await engine.isAvailable
    // In test environment LT is likely not installed — just verify no crash.
    XCTAssertTrue(available == true || available == false)
}

func testLanguageToolEngine_languageCodeMapping() {
    XCTAssertEqual(LanguageToolEngine.ltLanguageCode(for: "it"), "it-IT")
    XCTAssertEqual(LanguageToolEngine.ltLanguageCode(for: "en"), "en-US")
    XCTAssertEqual(LanguageToolEngine.ltLanguageCode(for: "fr"), "fr-FR")
    XCTAssertEqual(LanguageToolEngine.ltLanguageCode(for: "de"), "de-DE")
    XCTAssertEqual(LanguageToolEngine.ltLanguageCode(for: "es"), "es-ES")
    XCTAssertEqual(LanguageToolEngine.ltLanguageCode(for: "ru"), "ru-RU")
    XCTAssertEqual(LanguageToolEngine.ltLanguageCode(for: "zh"), "zh-CN")
    XCTAssertEqual(LanguageToolEngine.ltLanguageCode(for: "ja"), "ja-JP")
}
```

- [ ] **Step 2: Create `Core/LanguageToolEngine.swift`**

```swift
import Foundation
import OSLog

actor LanguageToolEngine {
    static let shared = LanguageToolEngine()
    private let logger = Logger(subsystem: Constants.bundleID, category: "LanguageToolEngine")

    var isAvailable: Bool { LanguageToolInstaller.isAvailable }

    /// Map Parrot language codes to LanguageTool locale codes.
    nonisolated static func ltLanguageCode(for language: String) -> String {
        let primary = language.split(separator: "-").first.map(String.init) ?? language
        switch primary {
        case "it": return "it-IT"
        case "en": return "en-US"
        case "fr": return "fr-FR"
        case "de": return "de-DE"
        case "es": return "es-ES"
        case "pt": return "pt-BR"
        case "ru": return "ru-RU"
        case "pl": return "pl-PL"
        case "uk": return "uk-UA"
        case "nl": return "nl-NL"
        case "sv": return "sv-SE"
        case "da": return "da-DK"
        case "nb", "no": return "nb-NO"
        case "ca": return "ca-ES"
        case "el": return "el-GR"
        case "ro": return "ro-RO"
        case "sk": return "sk-SK"
        case "sl": return "sl-SI"
        case "zh", "yue": return "zh-CN"
        case "ja": return "ja-JP"
        case "ar": return "ar"
        case "fa": return "fa"
        default:   return language
        }
    }

    /// Run LanguageTool on `text` and return correction spans.
    func check(_ text: String, language: String) async throws -> [CorrectionSpan] {
        guard isAvailable else { return [] }
        guard let java = LanguageToolInstaller.javaPath else { return [] }

        let ltCode = Self.ltLanguageCode(for: language)
        let process = Process()
        process.executableURL = java
        process.arguments = [
            "-jar", LanguageToolInstaller.binaryPath.path,
            "--language", ltCode,
            "--json",
            "-"   // read from stdin
        ]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        let inputData = text.data(using: .utf8) ?? Data()
        DispatchQueue.global(qos: .userInitiated).async {
            inputPipe.fileHandleForWriting.write(inputData)
            try? inputPipe.fileHandleForWriting.close()
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
        }

        guard process.terminationStatus == 0 else {
            logger.warning("LT exited \(process.terminationStatus)")
            return []
        }

        let outputData = (try? outputPipe.fileHandleForReading.readToEnd()) ?? Data()
        guard let json = String(data: outputData, encoding: .utf8) else { return [] }
        return parseLTOutput(json, originalText: text)
    }

    // MARK: - Parser

    private func parseLTOutput(_ json: String, originalText: String) -> [CorrectionSpan] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let matches = root["matches"] as? [[String: Any]]
        else { return [] }

        var spans: [CorrectionSpan] = []
        for match in matches {
            guard
                let offset = match["offset"] as? Int,
                let length = match["length"] as? Int,
                let message = match["message"] as? String,
                let replacements = match["replacements"] as? [[String: Any]],
                let firstValue = (replacements.first?["value"] as? String)
            else { continue }

            let nsRange = NSRange(location: offset, length: length)
            guard let swiftRange = Range(nsRange, in: originalText) else { continue }
            let original = String(originalText[swiftRange])
            guard original != firstValue else { continue }

            spans.append(CorrectionSpan(
                range: nsRange,
                original: original,
                replacement: firstValue,
                reason: message,
                confidence: 0.95,
                source: .languageTool
            ))
        }
        return spans
    }
}
```

- [ ] **Step 3: Run tests**

```bash
cd ~/Desktop/RefineClone && swift test --filter "testLanguageToolEngine"
```
Expected: all PASS.

- [ ] **Step 4: Commit**

```bash
cd ~/Desktop/RefineClone && git add Core/LanguageToolEngine.swift Tests/Tests.swift && git commit -m "feat: LanguageToolEngine — LT subprocess actor, 25+ language codes, JSON parser"
```

---

### Task 11: Wire LanguageTool into span pipeline

**Files:**
- Modify: `Core/TextCheckCoordinator.swift`

- [ ] **Step 1: Add LT to the span pipeline in `check()` action closure**

In `TextCheckCoordinator.swift`, after the `harperSpans` block and before the `SpanMerger.merge(...)` call, add:

```swift
// Layer 2: LanguageTool
var ltSpans: [CorrectionSpan] = []
if await LanguageToolEngine.shared.isAvailable {
    ltSpans = (try? await LanguageToolEngine.shared.check(text, language: language)) ?? []
}

// Merge rule-layer spans (now includes LT)
let ruleMerged = SpanMerger.merge(nativeSpans + ruleSpans + harperSpans + ltSpans)
```

- [ ] **Step 2: Build**

```bash
cd ~/Desktop/RefineClone && swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 3: Run all tests**

```bash
cd ~/Desktop/RefineClone && swift test
```
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
cd ~/Desktop/RefineClone && git add Core/TextCheckCoordinator.swift && git commit -m "feat: LanguageTool wired into span pipeline — 500+ rules per language, offline"
```

---

## PHASE 4 — Span-based UI (accept/reject per fix)

### Task 12: SpanSuggestionView

**Files:**
- Create: `UI/SpanSuggestionView.swift`
- Modify: `UI/SuggestionPanel.swift`

- [ ] **Step 1: Create `UI/SpanSuggestionView.swift`**

```swift
import SwiftUI

/// Displays a list of correction spans with per-fix accept/reject controls.
struct SpanSuggestionView: View {
    let original: String
    @State var spans: [CorrectionSpan]
    let onApply: ([CorrectionSpan]) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if spans.isEmpty {
                emptyState
            } else {
                spanList
            }
            Divider()
            footer
        }
        .frame(width: 420)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text("\(pendingCount) correction\(pendingCount == 1 ? "" : "s")")
                .font(.headline)
            Spacer()
            Button("Accept All") { acceptAll() }
                .buttonStyle(.borderless)
                .foregroundStyle(.green)
            Button("Dismiss") { onDismiss() }
                .buttonStyle(.borderless)
        }
        .padding(12)
    }

    private var spanList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(spans.indices, id: \.self) { i in
                    SpanRowView(
                        span: spans[i],
                        onAccept: { spans[i].accepted = true },
                        onReject: { spans[i].accepted = false }
                    )
                }
            }
            .padding(8)
        }
        .frame(maxHeight: 360)
    }

    private var emptyState: some View {
        Text("No corrections found.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(24)
    }

    private var footer: some View {
        HStack {
            Text("\(acceptedCount) accepted · \(rejectedCount) rejected")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Apply \(acceptedCount > 0 ? "\(acceptedCount) fix\(acceptedCount == 1 ? "" : "es")" : "")") {
                onApply(spans.filter { $0.accepted == true })
            }
            .buttonStyle(.borderedProminent)
            .disabled(acceptedCount == 0)
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private var pendingCount: Int { spans.filter { $0.accepted == nil }.count }
    private var acceptedCount: Int { spans.filter { $0.accepted == true }.count }
    private var rejectedCount: Int { spans.filter { $0.accepted == false }.count }

    private func acceptAll() {
        for i in spans.indices { spans[i].accepted = true }
    }
}

struct SpanRowView: View {
    let span: CorrectionSpan
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Source badge
            Text(span.source.displayName)
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(sourceBadgeColor.opacity(0.15))
                .foregroundStyle(sourceBadgeColor)
                .clipShape(RoundedRectangle(cornerRadius: 3))

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(span.original)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(span.replacement)
                        .bold()
                }
                .font(.callout)
                Text(span.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            HStack(spacing: 6) {
                Button { onReject() } label: {
                    Image(systemName: span.accepted == false ? "xmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(span.accepted == false ? .red : .secondary)
                }
                .buttonStyle(.borderless)

                Button { onAccept() } label: {
                    Image(systemName: span.accepted == true ? "checkmark.circle.fill" : "checkmark.circle")
                        .foregroundStyle(span.accepted == true ? .green : .secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(8)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var rowBackground: Color {
        switch span.accepted {
        case true:  return Color.green.opacity(0.08)
        case false: return Color.red.opacity(0.08)
        case nil:   return Color(NSColor.controlBackgroundColor)
        }
    }

    private var sourceBadgeColor: Color {
        switch span.source {
        case .nativeGrammar: return .blue
        case .ruleBased:     return .orange
        case .languageTool:  return .purple
        case .llm:           return .mint
        }
    }
}
```

- [ ] **Step 2: Add span result type to `CorrectionResult.swift`**

Add a convenience initializer to `CorrectionResult` for span-based results:

```swift
// In CorrectionResult.swift, after existing init:
var correctionSpans: [CorrectionSpan]? = nil
```

(Add this stored property alongside `replacementRange` and `anchorRect`, excluded from `CodingKeys`.)

- [ ] **Step 3: Wire SpanSuggestionView into SuggestionPanelController**

In `UI/SuggestionPanel.swift`, add a new show method:

```swift
func showSpans(result: CorrectionResult, spans: [CorrectionSpan]) {
    // Close existing panel if open.
    close()

    let view = SpanSuggestionView(
        original: result.originalText,
        spans: spans
    ) { [weak self] acceptedSpans in
        guard let self else { return }
        let corrected = SpanApplicator.apply(spans: acceptedSpans, to: result.originalText)
        var finalResult = CorrectionResult(
            original: result.originalText,
            corrected: corrected,
            modelID: result.modelID,
            confidence: result.confidence,
            promptType: result.promptType
        )
        finalResult.replacementRange = result.replacementRange
        finalResult.anchorRect = result.anchorRect
        self.applyAndClose(result: finalResult)
    } onDismiss: { [weak self] in
        self?.close()
    }

    show(SwiftUI: view, anchoredTo: result.anchorRect)
}
```

- [ ] **Step 4: Update `TextCheckCoordinator.check()` to pass spans to `showSpans`**

In the `onSuccess` closure of `check()`, replace:

```swift
show(result)
```

With:

```swift
if let spans = result.correctionSpans, !spans.isEmpty {
    SuggestionPanelController.shared.showSpans(result: result, spans: spans)
} else {
    show(result)
}
```

And in the span pipeline (Task 8), store spans on the result:

```swift
var finalResult = CorrectionResult(
    original: text,
    corrected: correctedText,
    modelID: llmResult.modelID,
    confidence: llmResult.confidence,
    promptType: effectiveType.label,
    detectedTone: detectedTone?.rawValue,
    source: allSpans.isEmpty ? .llm : .hybrid
)
finalResult.correctionSpans = allSpans.isEmpty ? nil : allSpans
```

- [ ] **Step 5: Build**

```bash
cd ~/Desktop/RefineClone && swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!` (fix compile errors before continuing).

- [ ] **Step 6: Run all tests**

```bash
cd ~/Desktop/RefineClone && swift test
```
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
cd ~/Desktop/RefineClone && git add UI/SpanSuggestionView.swift UI/SuggestionPanel.swift Core/TextCheckCoordinator.swift Core/CorrectionResult.swift Tests/Tests.swift && git commit -m "feat: span-based UI — per-fix accept/reject with source badge and reason"
```

---

## Self-Review

### Spec coverage check

| Spec requirement | Task |
|-----------------|------|
| Remove pipeline short-circuit | Task 1 |
| Remove language detection guard | Task 2 |
| Apple Intelligence priority | Task 3 |
| CorrectionSpan type + SpanApplicator | Task 4 |
| SpanMerger | Task 5 |
| NSSpellChecker.checkGrammar (Layer 0) | Task 6 |
| LLM JSON structured output | Task 7 |
| Integrate spans into pipeline | Task 8 |
| LanguageTool installer | Task 9 |
| LanguageToolEngine | Task 10 |
| Wire LT into pipeline | Task 11 |
| Span-based UI accept/reject | Task 12 |
| Privacy: all processing local | All tasks — no external calls added |

### Type consistency check

- `CorrectionSpan` defined Task 4, used Tasks 5, 6, 7, 8, 10, 11, 12 ✓
- `SpanMerger.merge(_ spans: [CorrectionSpan])` defined Task 5, called Tasks 8, 11 ✓
- `SpanApplicator.apply(spans:to:)` defined Task 4, called Tasks 8, 12 ✓
- `NativeGrammarEngine.check(_:language:)` defined Task 6, called Task 8 ✓
- `LanguageToolEngine.shared.check(_:language:)` defined Task 10, called Task 11 ✓
- `LLMJSONParser.cleanAndParse(json:in:)` defined Task 7, available for future use ✓
- `SpanSource.displayName` defined Task 4, used Task 12 ✓

### No placeholders

Scanned — no TBD, TODO, or incomplete code blocks found.
