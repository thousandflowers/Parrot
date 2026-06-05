# Style Learning — Design Spec

**Date:** 2026-05-29
**Status:** Approved design, pre-implementation
**Author:** Eugenio

## Goal

Parrot learns the user's own writing style and adapts rewrites to it. Style is profiled
**per language** and **per recipient** (specific contact, or formality register, or general).
Learning is on-device, automatic, and inspectable. The user can also feed style explicitly
via pasted samples or bulk text import. Imported facts (names/info) keep using the existing
`KnowledgeBase` and `ContactStore`; this feature links style profiles to contacts by UUID.

### Non-goals
- No cloud/network. Everything is on-device.
- No style applied to **grammar** correction — grammar stays minimal-edit to avoid the
  over-correction problem already fixed for small models. Style applies to fluency / expand /
  combined rewrites only.
- No LLM-generated style summaries. Features are deterministic; exemplars are verbatim user text.

## Decisions (from brainstorming)

| Question | Decision |
|----------|----------|
| Learning sources | Passive (accepted/written text) + explicit samples + bulk import |
| Representation | Deterministic statistical features **+** 2–3 representative exemplars |
| Recipient segmentation | Hierarchy: **contact → register → language** (fallback up the chain) |
| Where style is applied | Fluency / Expand / Combined rewrites only — **never grammar** |
| Control & privacy | Auto-on, on-device, with a Settings tab to inspect / edit / reset / add samples / import |

## Data Model

```
enum StyleRecipient: Sendable, Hashable, Codable
  case contact(UUID)
  case register(StyleRegister)   // formal | informal | neutral
  case general

enum StyleRegister: String, Codable, Sendable   // formal, informal, neutral

struct StyleScope: Hashable, Codable, Sendable
  language: String               // primary code, e.g. "it"
  recipient: StyleRecipient
  var key: String                // "it|contact:<uuid>", "it|register:formal", "it|general"

struct StyleFeatures: Codable, Sendable, Equatable    // all deterministic
  avgSentenceLength: Double      // words per sentence
  avgWordLength: Double
  formalityScore: Double         // 0 (informal) .. 1 (formal)
  emojiRate: Double              // emoji per 100 words
  exclamationRate: Double        // '!' per sentence
  questionRate: Double           // '?' per sentence
  contractionRate: Double        // informal contractions per 100 words (lang-specific)
  greetings: [String: Int]       // detected opener -> frequency
  closings: [String: Int]        // detected closer -> frequency

struct StyleProfile: Identifiable, Codable, Sendable
  id: String                     // == scope.key
  scope: StyleScope
  sampleCount: Int
  features: StyleFeatures
  exemplars: [String]            // <= 3 verbatim snippets, each 20..300 chars
  updatedAt: Date
```

### Register derivation
`ToneDetector.detect(text:language:)` returns `formal | informal | neutral | academic | technical`.
Map to `StyleRegister`: `academic`/`technical`/`formal → .formal`, `informal → .informal`,
`neutral → .neutral`.

## Components (isolated units)

### 1. Models — `Core/Style/StyleModels.swift`
`StyleRecipient`, `StyleRegister`, `StyleScope`, `StyleFeatures`, `StyleProfile`. Pure value types.
- *Does:* define the vocabulary of the feature.
- *Depends on:* Foundation only.

### 2. `StyleAnalyzer` — `Core/Style/StyleAnalyzer.swift` (enum, pure functions)
- `features(for text: String, language: String) -> StyleFeatures`
- `register(for text: String, language: String) -> StyleRegister` (wraps `ToneDetector`)
- `detectGreeting(...)`, `detectClosing(...)` — first/last line pattern match against a small
  per-language opener/closer list (e.g. it: "Ciao", "Gentile", "Salve"; "Cordiali saluti", "A presto").
- *Reuses:* `Lexicon` (informalWords, contractions, computeWordScores), `ToneDetector`, `LanguageFamily`.
- *Depends on:* Models, Lexicon, ToneDetector. No state, no I/O.

### 3. `StyleLearningStore` — `Infra/StyleLearningStore.swift` (actor)
Persisted JSON at `Application Support/Parrot/style_profiles.json`.
- `observe(text:language:recipient:) async` — skip if `< 3` words. Compute features via
  `StyleAnalyzer`, merge into the scope's profile with a **sample-count-weighted running average**
  (`new = (old*n + sample) / (n+1)`), merge greeting/closing counts, update exemplar reservoir,
  bump `sampleCount`, set `updatedAt`.
- `importSamples(texts:[String], language:recipient:) async` — calls `observe` per text.
- `profile(language:recipient:) async -> StyleProfile?` — resolves with fallback:
  `contact → register(of current text) → general`. Returns the first scope that has
  `sampleCount >= minSamplesForUse` (default 3); else nil.
- UI surface: `allProfiles() -> [StyleProfile]`, `update(_:)`, `reset(scopeKey:)`, `deleteAll()`.
- *Depends on:* Models, StyleAnalyzer. Persistence mirrors `ContactStore`/`KnowledgeBase` patterns.

#### Exemplar reservoir (v1)
Keep ≤3 per profile. On `observe`, if the text length is in `20..300` chars, add it; if already 3,
replace the exemplar whose features are **farthest** from the updated profile centroid (keep the
3 most representative). Deterministic, no randomness.

### 4. `StyleHintBuilder` — `Core/Style/StyleHintBuilder.swift` (enum, pure)
`build(from profile: StyleProfile) -> (summary: String, examples: [String])`
- `summary`: one line, e.g.
  `"User style: informal, short sentences (~12 words), frequent '!', greeting 'Ciao', closing 'A presto'. Match this voice; do not change meaning."`
- `examples`: the profile's exemplars.
- Only emits fields that are meaningful (skip zero-rate fields).

### 5. Prompt injection — `Core/PromptEngine.swift`
Add an optional `styleProfile: StyleProfile?` to `buildFluencyPrompt`, `buildExpandPrompt`,
`buildCombinedPrompt`. When present, append a `Match this writing style:` block (summary + examples
as few-shot). **`buildGrammarPrompt` / `buildGrammarJSONPrompt` are untouched.**
The existing `StyleProfiler.buildHint` (rejection-based) remains for grammar as today.

### 6. Recipient resolution & ingestion wiring — `Core/TextCheckCoordinator.swift`
- A helper `resolveRecipient(text:bundleID:) async -> StyleRecipient`:
  `ContactStore.findInText(text)` → `.contact(id)`; else `.register(StyleAnalyzer.register(...))`;
  else `.general`.
- **Apply path (passive learning):** in `SuggestionPanel.applyCorrection()` and
  `applyAndClose(result:)` — after `replaceSelectedText(with: result.correctedText)` succeeds,
  call `StyleLearningStore.shared.observe(text: result.correctedText, language:, recipient:)`.
  The accepted/applied text is the ground-truth style sample.
- **Request path (use):** before building a fluency/expand/combined prompt, the coordinator fetches
  `StyleLearningStore.shared.profile(language:recipient:)` and threads it to `PromptEngine`.

### 7. UI — `UI/StyleTab.swift` + `SettingsView` wiring
New `.style` case in `SettingsTab`, added to `dataTabs`, routed in `destination(...)`.
- Profiles grouped by language → recipient. Each row shows metrics (sentence length, formality,
  emoji/!/? rates, greeting/closing) and exemplars.
- Actions: edit exemplars/notes, **Reset** a scope, **Delete all**.
- **Add sample**: paste text + pick language + recipient (contact picker / register / general).
- **Import texts**: file picker (multi `.txt`/`.md`), bulk `importSamples`.

## Data Flow

```
Rewrite request (fluency/expand/combined)
  Coordinator: detect language -> resolveRecipient(text,bundleID)
  -> StyleLearningStore.profile(language, recipient)   (fallback contact->register->general)
  -> StyleHintBuilder.build(profile)
  -> PromptEngine.buildFluencyPrompt(..., styleProfile:)   [grammar path skips this]
  -> LLM

User accepts result (SuggestionPanel.applyCorrection / applyAndClose)
  -> replaceSelectedText(correctedText)
  -> StyleLearningStore.observe(correctedText, language, recipient)   [merge + reservoir]
```

## Error Handling
- No profile / `< minSamplesForUse` → no injection (rewrite behaves as today).
- Corrupt `style_profiles.json` → log via `CrashLogger`, start with empty store (never crash).
- `observe` ignores text `< 3` words and exemplars outside `20..300` chars.
- All persistence is atomic writes (match existing stores). All data on-device; user can reset/delete.

## Testing
- `StyleAnalyzer` feature extraction: per-language fixtures (it/en) for sentence length, formality,
  emoji/!/?, contractions, greeting/closing detection.
- Register mapping from `ToneDetector` tones.
- `StyleLearningStore` fallback resolution: contact → register → general → nil.
- Running-average merge math across multiple `observe` calls.
- Exemplar reservoir: cap at 3, representative replacement is deterministic.
- `StyleHintBuilder` output: omits zero-rate fields; stable format.
- Injection guard: `buildFluencyPrompt`/`buildExpandPrompt` include style block; `buildGrammarPrompt`
  does NOT (regression guard against over-correction).

## Implementation Phases
- **Phase 1 (core value):** Models + `StyleAnalyzer` + `StyleLearningStore` + `StyleHintBuilder` +
  PromptEngine injection (fluency/expand/combined) + passive ingestion on apply + recipient resolution.
- **Phase 2 (control):** `StyleTab` UI — inspect / edit / reset / add sample / import.
- **Phase 3 (refinement):** exemplar selection tuning, register detection tuning, more languages
  for greeting/closing lists.

## Open Risks
- Recipient detection accuracy depends on `ContactStore.findInText`; when wrong, falls back to
  register — acceptable degradation.
- Exemplar privacy: snippets are user text stored locally; surfaced and resettable in the UI.
- Style vs correctness tension: mitigated by excluding grammar entirely.
