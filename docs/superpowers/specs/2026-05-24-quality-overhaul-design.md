# Parrot — Quality Overhaul Design

**Date:** 2026-05-24  
**Goal:** Massima qualità correzione grammaticale per tutte le lingue, 100% offline, zero dati escono dalla macchina senza consenso esplicito.

---

## Constraints

- 100% offline by default
- No data leaves the machine unless user explicitly enables remote services
- macOS 14+ support (FoundationModels requires macOS 26)
- Apple Silicon primary target (M2 Pro, 16GB)
- High quality across: IT, EN, FR, DE, ES, PT, RU, ZH, JA and others
- Super efficient: corrections in <3s for typical selections (<500 words)

---

## Current Problems

1. **Pipeline short-circuit**: rule engine finds one fix → LLM skipped → complex errors ignored
2. **validateCorrection fragility**: language detection on error-heavy text → valid corrections discarded silently
3. **fewShotExamples() dead code**: defined for 10 languages, never called (fixed 2026-05-24)
4. **wordChangeFraction set-based bug**: short sentences hit 65% threshold incorrectly (fixed 2026-05-24)
5. **Full-text replace**: all-or-nothing, no granular accept/reject
6. **NSSpellChecker.checkGrammar() unused**: built-in macOS grammar API never called
7. **No structured LLM output**: raw text → fragile heuristic parsing

---

## Target Architecture

```
selected text
      │
      ▼
[Layer 0] NSSpellChecker.checkGrammar()
          Built-in macOS, zero deps, 15+ languages, span-based, <10ms
      │ []CorrectionSpan
      ▼
[Layer 1] RuleBasedEngine (existing, expanded)
          Custom regex rules, fast, per-language
      │ []CorrectionSpan
      ▼
[Layer 2] LanguageTool (local subprocess)
          500+ rules/language, 25+ languages, span-based, offline
          Distributed as GraalVM native binary (no JVM) ~120MB
          Or: languagetool-commandline.jar + bundled JRE
      │ []CorrectionSpan
      ▼
[Layer 3] LLM — contextual/morphological errors only
          Priority: Apple Intelligence > Ollama > llama-server > Remote
          Output: JSON structured {"corrections": [{original, replacement, reason}]}
          Called only when layers 0-2 leave uncovered errors (heuristic)
      │ []CorrectionSpan
      ▼
[SpanMerger]
          Deduplicate overlapping spans
          Ranking: Layer0 < RuleBased < LanguageTool < LLM
          Output: non-overlapping sorted []CorrectionSpan
      │
      ▼
[UI] Span-based SuggestionPanel
          Each fix shown individually with reason
          Accept / Reject per fix
          Accept All / Reject All
          Apply only accepted spans to original text
```

---

## New Data Type: CorrectionSpan

```swift
struct CorrectionSpan: Sendable, Identifiable {
    let id: UUID
    let range: NSRange          // character range in original text
    let original: String        // text at that range
    let replacement: String     // suggested correction
    let reason: String          // human-readable explanation
    let confidence: Double      // 0.0-1.0
    let source: SpanSource      // .nativeGrammar, .ruleBased, .languageTool, .llm
    var accepted: Bool?         // nil = pending, true = accepted, false = rejected
}

enum SpanSource: Int, Comparable {
    case nativeGrammar = 0
    case ruleBased = 1
    case languageTool = 2
    case llm = 3
    
    static func < (lhs: SpanSource, rhs: SpanSource) -> Bool { lhs.rawValue < rhs.rawValue }
}
```

---

## Component Designs

### NativeGrammarEngine

New actor wrapping `NSSpellChecker.checkGrammar()`.

```swift
actor NativeGrammarEngine {
    func check(_ text: String, language: String) -> [CorrectionSpan]
}
```

- Calls `NSSpellChecker.shared.checkGrammar(of:startingAt:language:wrap:inSpellDocumentWithTag:details:)` in a loop
- Converts `NSGrammarDetail` to `CorrectionSpan`
- Returns immediately (synchronous under the hood, no subprocess)

### LanguageToolEngine

New actor managing LT subprocess.

```swift
actor LanguageToolEngine {
    var isAvailable: Bool
    func check(_ text: String, language: String) async throws -> [CorrectionSpan]
}
```

- Manages LT binary (commandline mode, not HTTP server — simpler for privacy)
- Binary location: `Parrot.app/Contents/MacOS/languagetool` (GraalVM native) or JAR
- Input via stdin, output via stdout (JSON)
- Per-check subprocess spawn (simpler than daemon; ~200ms overhead acceptable)
- Language code mapping: Parrot "it" → LT "it-IT", "en" → "en-US", etc.
- Distributed: downloaded by Parrot on first use or bundled

### LLM JSON Output

Changes to `LLMServiceExtension.performCorrection()`:

Instead of asking for raw corrected text:
```
Fix the text and return JSON:
{"corrections": [{"original": "...", "replacement": "...", "reason": "..."}]}
Return empty array if no corrections needed.
```

Response parsing: `JSONDecoder` → `[LLMCorrection]` → `[CorrectionSpan]`

Structured output enforced via:
- llama.cpp: `response_format: {type: "json_object"}`
- Ollama: `format: "json"`
- Apple Intelligence: prompt-enforced (no format parameter yet)
- Remote OpenAI: `response_format: {type: "json_object"}`

### SpanMerger

```swift
struct SpanMerger {
    static func merge(_ spans: [[CorrectionSpan]]) -> [CorrectionSpan]
}
```

Algorithm:
1. Flatten all spans, sort by range start
2. For overlapping spans: keep highest `SpanSource` (LLM > LT > rule > native)
3. Remove remaining overlaps
4. Return non-overlapping array sorted by range start

### Pipeline Changes (TextCheckCoordinator)

Remove the short-circuit:
```swift
// REMOVE THIS:
if (hasCustomFixes || hasRuleFixes) && language != "en" {
    return CorrectionResult(... source: .ruleBased)
}
```

New flow: always run all layers, merge spans.

Remove language detection guard in `performCorrection`:
```swift
// REMOVE THIS:
let inLang  = LanguageDetector.detect(text: text, ...)
let outLang = LanguageDetector.detect(text: validated, ...)
corrected = (outLang == inLang) ? validated : text
```

With JSON structured output this guard is no longer needed.

### Span-based SuggestionPanel UI

New `SpanSuggestionView` component:
- Shows original text with colored underlines at error spans
- Sidebar or inline popover for each span: reason + replacement
- Keyboard shortcuts: ⏎ accept, ⌫ reject, ⌘A accept all
- Apply button: reconstructs corrected text from accepted spans

Keep existing full-text view as fallback for fluency/translation/coach modes.

---

## LLM Backend Priority

```swift
// LLMServiceFactory — new priority resolution
static func resolveGrammarService() -> LLMService {
    if #available(macOS 26.0, *), AppleIntelligenceService.shared.isAvailable {
        return AppleIntelligenceService.shared  // NPU, private, fast
    }
    if OllamaService.shared.isConfigured {
        return OllamaService.shared             // Qwen 2.5 7B+ recommended
    }
    return LocalLLMService.shared               // llama-server fallback
}
// RemoteLLMService only used if user explicitly enables it
```

---

## LanguageTool Distribution

**Option A (recommended): Download on first use**
- Parrot checks for LT binary at `~/Library/Application Support/Parrot/LanguageTool/lt`
- If missing: show one-time download prompt (~120MB GraalVM native binary)
- Downloaded from GitHub releases of languagetool project
- SHA-256 verified before use
- Privacy: binary is local, text processed locally, nothing sent externally

**Option B: Bundle in app**
- App size ~300MB
- Zero setup
- Harder to update LT independently

Recommendation: Option A. Same pattern as model downloading (ModelManager already handles this).

---

## Implementation Phases

### Phase 1 — Immediate pipeline fixes (high impact, low risk)
- Remove short-circuit (rules → always continue to LLM)
- Remove language detection guard
- Fix Apple Intelligence as priority backend
- LLM JSON structured output
- `NativeGrammarEngine` (NSSpellChecker.checkGrammar)

### Phase 2 — CorrectionSpan data model
- `CorrectionSpan` type
- `SpanMerger`
- All engines produce `[CorrectionSpan]`
- Keep existing UI (full-text display from merged spans)

### Phase 3 — LanguageTool integration
- `LanguageToolEngine` actor
- Download manager (reuse ModelManager pattern)
- Language code mapping (25+ languages)
- Integration into pipeline

### Phase 4 — Span-based UI
- `SpanSuggestionView`
- Per-fix accept/reject
- Keyboard navigation
- Apply reconstructed text

---

## Privacy Guarantee

- Layers 0, 1, 2: 100% local processing, zero network
- Layer 3 LLM: local by default (Apple Intelligence / Ollama / llama-server)
- Remote services (RemoteLLMService, OpenRouterService): only active if user explicitly configures API key and selects remote model in Settings
- No telemetry, no crash reporting to external servers (CrashLogger writes to ~/Library/Logs/Parrot/ only)
