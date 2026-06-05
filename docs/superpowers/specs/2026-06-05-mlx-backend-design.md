# MLX Backend — Design Spec

Date: 2026-06-05
Status: approved, ready for implementation plan
Scope: Add an on-device MLX inference backend (`MLXLLMService`) as a peer to the
existing local (llama.cpp) / remote / ollama / openRouter / appleIntelligence
backends, selectable in settings.

> **Important constraint:** Inference cannot be verified headless in CI — it
> requires a Metal device and a multi-GB MLX model download. The implementation
> session must build against the real MLXLLM API (slow Metal compiles) and the
> user must smoke-test generation on-device. Only the plumbing (service type,
> factory routing, settings, model-id resolution) is unit-testable.

---

## Background & motivation

From `Desktop/Wren - cose da fare.md` and competitive research: Apple MLX runs
~2-3× faster than llama.cpp on Apple Silicon and is explicitly requested by users.
Wren already abstracts inference behind the `LLMService` protocol with multiple
backends, so MLX is an additive backend, not a rewrite.

### Existing architecture (the seam MLX plugs into)

- `protocol LLMService` (`Core/LLMService.swift`): `correct(text:promptType:language:)`,
  `correctFluency(text:)`, `explain(original:corrected:)`,
  `streamCorrect(text:promptType:)`, `handleOpenAIHTTPStatus(_:data:)`.
- `enum ServiceType` (`Core/LLMService.swift`): stub/local/remote/ollama/openRouter/appleIntelligence.
- `LLMServiceFactory` (`Core/LLMServiceFactory.swift`): maps `ServiceType` → singleton service,
  resolves model id + fallback model id per type.
- Shared helpers in `Core/LLMServiceExtension.swift`: `resolvedLanguage`, `resolveStyle()`,
  `validateCorrection(original:corrected:isFluency:)` — used by every in-process service.
- `AppleIntelligenceService` (`Core/AppleIntelligenceService.swift`) is the closest
  template: an `actor` conforming to `LLMService` that builds prompts via `PromptEngine`,
  calls a `generate(_:)` primitive, and validates output.

### Dependency feasibility (verified 2026-06-05)

`swift package resolve` succeeds for:
- `github.com/ml-explore/mlx-swift-examples` → 1.18.2 (products `MLXLLM`, `MLXLMCommon`)
- transitively: `mlx-swift` 0.31.4, `huggingface/swift-transformers` 0.1.24, `GzipSwift`.

MLX core (`MLX`) only provides tensor ops; LLM generation + tokenizer + HF model
download come from `MLXLLM`/`MLXLMCommon`. `LLMModelFactory` downloads the model
from the HuggingFace Hub on first load with a progress callback, so Wren does not
need to build a separate MLX download pipeline — model management reduces to
storing the selected repo id and surfacing load/download progress.

---

## Goals

- `MLXLLMService` conforms to `LLMService`, generating corrections fully on-device via MLX.
- Selectable as a backend (`ServiceType.mlx`) in settings, with a model-id field.
- Graceful degradation: if MLX is unavailable (non–Apple-Silicon, load failure),
  fall back like other unsupported backends do (to `.stub`/error), never crash.
- Model loaded once and cached (`ModelContainer`), reused across corrections.
- Plumbing is unit-tested; inference is user-smoke-tested.

## Non-goals (deferred)

- Latency benchmark MLX vs llama.cpp (separate measurement task; needs device).
- MLX for the inline-completion helper subprocess (this spec is correction-path only;
  completion runs in `ParrotCompletionHelper` via CLlama and is out of scope).
- A custom in-app MLX model browser (reuse the existing model settings + a repo-id field).
- Quantization/conversion tooling (users pick pre-quantized `mlx-community/*` repos).

---

## Architecture

### New service: `MLXLLMService`

`actor MLXLLMService: LLMService`, singleton `static let shared`. Modeled on
`AppleIntelligenceService`. Holds a lazily-loaded `ModelContainer` keyed by the
selected model id; reloads when the id changes.

```
correct(text:promptType:language:)   → build prompt (PromptEngine + resolveStyle) → generate → validateCorrection
correctFluency(text:)                → correct(text:, promptType: .fluency, language: "")
explain(original:corrected:)         → buildExplainPrompt → generate
streamCorrect(text:promptType:)      → AsyncThrowingStream, token callback from MLX generate
handleOpenAIHTTPStatus(_:data:)      → not network-based; map to no-op/200 like AppleIntelligence
```

Core primitive:
```
private func generate(_ prompt: String) async throws -> String
```
loads/reuses the `ModelContainer`, runs `MLXLMCommon` generation, returns trimmed text.

Availability:
```
nonisolated var isAvailable: Bool          // Apple Silicon + model id set
nonisolated var availabilityDescription: String
```

### Model loading & caching

- Selected model id stored under `Constants.UserDefaultsKey.mlxModelID`
  (e.g. `mlx-community/Qwen2.5-1.5B-Instruct-4bit`).
- `MLXLLMService` keeps `private var container: ModelContainer?` and
  `private var loadedModelID: String?`. On `generate`, if `loadedModelID != current`,
  load via `LLMModelFactory.shared.loadContainer(configuration:)` with a progress
  handler that updates a published load-progress signal for the UI.
- Load failures map to `CorrectionError.modelDownloadFailed` / `.modelNotLoaded`.

### Factory & service-type wiring

- Add `case mlx` to `ServiceType`.
- `LLMServiceFactory.make(with:)`: `.mlx` → `MLXLLMService.shared` (guarded by an
  Apple-Silicon/availability check; fall back to `.stub` with a warning log otherwise,
  mirroring the `appleIntelligence` macOS-version guard).
- `resolveModelID(for: .mlx)` → `mlxModelID` (default `mlx-community/Qwen2.5-1.5B-Instruct-4bit`).
- `resolveFallbackModelID(for: .mlx)` → `fallbackMlxModelID` (optional).
- `RequestQueue` model-id key switch: `.mlx` → `mlxModelID`.

### Settings / UI

- `ServiceStep` (engine picker) + `MenuBarView` (label `MLX · <model>`, icon e.g.
  `cpu.fill` or `bolt`, status line) gain a `.mlx` case.
- A text field for the MLX repo id (reuse the pattern used for ollama/openRouter model fields).
- Optional: a small load/download progress indicator when the model is first fetched.

### Constants & preferences

- New keys: `mlxModelID`, `fallbackMlxModelID`.
- `PreferencesStore`: `mlxModel: String` (get/set), default
  `"mlx-community/Qwen2.5-1.5B-Instruct-4bit"`.

### Package.swift

Add to root `dependencies`:
```swift
.package(url: "https://github.com/ml-explore/mlx-swift-examples.git", from: "1.18.0"),
```
Add to the `Parrot` target `dependencies`:
```swift
.product(name: "MLXLLM", package: "mlx-swift-examples"),
.product(name: "MLXLMCommon", package: "mlx-swift-examples"),
```
Note: this pulls MLX + swift-transformers + Metal kernel compilation → significantly
longer clean builds and a larger app binary. Acceptable for the feature; call it out
in the PR.

---

## Generation API note (must be reconciled at implementation time)

The `MLXLMCommon` generation API is version-sensitive (1.18.x). The canonical pattern is:

```swift
import MLXLLM
import MLXLMCommon

let config = ModelConfiguration(id: modelID)
let container = try await LLMModelFactory.shared.loadContainer(configuration: config) { progress in
    // report download/load fraction
}
let output = try await container.perform { context in
    let input = try await context.processor.prepare(input: UserInput(prompt: prompt))
    var text = ""
    let result = try MLXLMCommon.generate(
        input: input,
        parameters: GenerateParameters(temperature: 0.3),
        context: context
    ) { tokens in
        // optional incremental decode for streaming
        return .more
    }
    text = context.tokenizer.decode(tokens: result.tokens)
    return text
}
```

The exact symbol names (`UserInput`, `GenerateParameters`, `generate` signature,
`container.perform`) MUST be confirmed against the resolved `MLXLMCommon` 1.18.2
headers during implementation — the plan's first build step exists to surface and
fix any API drift. Do not assume this snippet compiles verbatim.

---

## Testing

### Unit (CI-safe, no Metal/model)
- `ServiceType(rawValue: "mlx") == .mlx`; round-trips through Codable.
- `LLMServiceFactory.resolveModelID(for: .mlx)` returns the configured/default mlx id.
- `LLMServiceFactory.make(with: .mlx)` returns an `MLXLLMService` on Apple Silicon,
  or `.stub` when guarded unavailable (test the guard via an injectable availability flag).
- `PreferencesStore.mlxModel` default + set/get.

### On-device smoke (user, documented checklist)
- Pick MLX engine + a `mlx-community/*` repo id → first correction triggers model
  download with visible progress → subsequent corrections are fast.
- Grammar + fluency corrections produce sane output in the input language.
- Switching model id reloads the container.
- Non–Apple-Silicon or bad repo id → graceful error, no crash, fallback works.

---

## Files

New:
- `Core/MLXLLMService.swift`
- (tests) `Tests/MLXBackendTests.swift`

Modified:
- `Package.swift` (dependency + target products)
- `Core/LLMService.swift` (`ServiceType.mlx`)
- `Core/LLMServiceFactory.swift` (make / resolveModelID / resolveFallbackModelID)
- `Core/RequestQueue.swift` (model-id key switch)
- `App/Constants.swift` (`mlxModelID`, `fallbackMlxModelID`)
- `Infra/PreferencesStore.swift` (`mlxModel`)
- `UI/ServiceStep.swift`, `UI/MenuBarView.swift` (engine picker + labels/icons)

---

## Risks

- **Build weight:** MLX + transformers + Metal kernels → slow clean builds, bigger
  binary. Mitigation: accept; document; the dependency only affects the main target.
- **API drift:** MLXLMCommon generation API changes across versions. Mitigation:
  pin `from: "1.18.0"`; the implementation's first step is a compile-and-fix pass.
- **Untestable inference in CI:** Mitigation: isolate all MLX calls inside
  `MLXLLMService.generate`; keep everything else (routing, prefs, prompts) testable;
  rely on the documented on-device smoke checklist.
- **Apple Silicon only:** MLX requires it. Mitigation: availability guard + fallback,
  same pattern as the macOS-26 guard for Apple Intelligence.
