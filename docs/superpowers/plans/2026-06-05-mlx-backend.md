# MLX Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an on-device MLX inference backend (`MLXLLMService`) selectable as a peer to the existing llama.cpp/remote/ollama/openRouter/appleIntelligence backends.

**Architecture:** New `actor MLXLLMService: LLMService` modeled on `AppleIntelligenceService`, loading a cached `ModelContainer` via `MLXLLM`/`MLXLMCommon` (HF Hub download on first use). All MLX calls are isolated inside `generate`; routing/prefs/prompts stay testable. `ServiceType.mlx` threads through factory, settings, and request queue.

**Tech Stack:** Swift, `mlx-swift-examples` (MLXLLM, MLXLMCommon) → mlx-swift + swift-transformers. Build: `swift build` (slow — Metal kernels). Test: `swift test`. Run all commands from `core/`.

> **Reality check (from spec):** Inference needs a Metal device + multi-GB model
> download. CI cannot verify generation. Tasks 1, 4 are unit-testable; Tasks 2, 3 are
> build-verified; final generation is an on-device smoke checklist for the user.

---

## File Structure

New:
- `Core/MLXLLMService.swift` — the backend.
- `Tests/MLXBackendTests.swift` — plumbing tests (enum, factory, prefs).

Modified:
- `Package.swift` — dependency + target products.
- `Core/LLMService.swift` — `ServiceType.mlx`.
- `Core/LLMServiceFactory.swift` — make / resolveModelID / resolveFallbackModelID.
- `Core/RequestQueue.swift` — model-id key switch.
- `App/Constants.swift` — `mlxModelID`, `fallbackMlxModelID`.
- `Infra/PreferencesStore.swift` — `mlxModel`.
- `UI/MenuBarView.swift`, `UI/ServiceStep.swift` — engine picker label/icon + model field.

---

## Task 1: ServiceType.mlx + plumbing (no dependency yet)

Add the case and thread it through every exhaustive switch so the project still
builds, with the factory temporarily routing `.mlx` to `.stub` (real service in Task 3).

**Files:**
- Modify: `Core/LLMService.swift`, `App/Constants.swift`, `Infra/PreferencesStore.swift`,
  `Core/LLMServiceFactory.swift`, `Core/RequestQueue.swift`, `UI/MenuBarView.swift`, `UI/ServiceStep.swift`
- Test: `Tests/MLXBackendTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MLXBackendTests.swift`:

```swift
import XCTest
@testable import Parrot

@MainActor
final class MLXBackendTests: XCTestCase {
    func testServiceType_mlxRawValueRoundTrips() {
        XCTAssertEqual(ServiceType(rawValue: "mlx"), .mlx)
        XCTAssertEqual(ServiceType.mlx.rawValue, "mlx")
    }

    func testResolveModelID_mlxUsesPreference() {
        UserDefaults.standard.set("mlx-community/Test-Model-4bit", forKey: Constants.UserDefaultsKey.mlxModelID)
        XCTAssertEqual(LLMServiceFactory.resolveModelID(for: .mlx), "mlx-community/Test-Model-4bit")
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.mlxModelID)
    }

    func testMlxModelPreference_hasDefault() {
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.mlxModelID)
        XCTAssertFalse(PreferencesStore.shared.mlxModel.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MLXBackendTests`
Expected: FAIL — `.mlx` not a member / `mlxModelID` not found.

- [ ] **Step 3: Add the enum case**

In `Core/LLMService.swift`, add `case mlx` to `ServiceType`:

```swift
enum ServiceType: String, Codable, CaseIterable {
    case stub
    case local
    case remote
    case ollama
    case openRouter
    case appleIntelligence
    case mlx
}
```

- [ ] **Step 4: Add Constants keys**

In `App/Constants.swift`, alongside the other model keys (near `openRouterModel`):

```swift
        static let mlxModelID = "mlxModelID"
        static let fallbackMlxModelID = "fallbackMlxModelID"
```

- [ ] **Step 5: Add the preference**

In `Infra/PreferencesStore.swift`, near the other model prefs:

```swift
    var mlxModel: String {
        get { string(Constants.UserDefaultsKey.mlxModelID, fallback: "mlx-community/Qwen2.5-1.5B-Instruct-4bit") }
        set { set(newValue, for: Constants.UserDefaultsKey.mlxModelID) }
    }
```

(If `string(_:fallback:)` is not the exact helper name, match the signature used by
`ollamaModel`/`openRouterModel` in the same file.)

- [ ] **Step 6: Thread through the factory**

In `Core/LLMServiceFactory.swift`:

`make(with:)` — add (temporary stub routing; real service in Task 3):
```swift
        case .mlx:
            // Real MLXLLMService wired in Task 3 once the dependency is added.
            Logger.infra.warning("MLX backend not yet wired, falling back to .stub")
            return StubLLMService.shared
```

`resolveModelID(for:)` — add:
```swift
        case .mlx:
            return UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.mlxModelID)
                ?? "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
```

`resolveFallbackModelID(for:)` — add to the switch:
```swift
        case .mlx:     key = Constants.UserDefaultsKey.fallbackMlxModelID
```

- [ ] **Step 7: Thread through RequestQueue**

In `Core/RequestQueue.swift` model-id key switch (near `case .openRouter`):
```swift
        case .mlx:        return Constants.UserDefaultsKey.mlxModelID
```

- [ ] **Step 8: Fix UI exhaustive switches (minimal labels)**

In `UI/MenuBarView.swift`, add `.mlx` to the label switch and icon switch:
```swift
        case .mlx:               return "MLX · \(prefs.mlxModel)"
```
```swift
        case .mlx:               return "bolt"
```
And to any other exhaustive `ServiceType` switch the compiler flags in this file
(e.g. the engine-detail block near `.appleIntelligence`) with a sensible MLX equivalent.

In `UI/ServiceStep.swift`, add a `.mlx` branch mirroring the `.ollama`/`.openRouter`
model-field branches (a text field bound to `prefs.mlxModel`, labeled "MLX model (HuggingFace repo id)").

- [ ] **Step 9: Build + run tests**

Run: `swift build` → Expected: `Build complete!`
Run: `swift test --filter MLXBackendTests` → Expected: PASS (3).
Run: `swift test` → Expected: all pass, 0 failures.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat(mlx): ServiceType.mlx + plumbing (factory, prefs, settings) routed to stub"
```

---

## Task 2: Add the MLX dependency

Pull `mlx-swift-examples` into the build before writing the service.

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Add the package dependency**

In `Package.swift`, add to the root `dependencies` array:
```swift
        .package(url: "https://github.com/ml-explore/mlx-swift-examples.git", from: "1.18.0"),
```

- [ ] **Step 2: Add the products to the Parrot target**

In the `Parrot` `.executableTarget` `dependencies` array, add:
```swift
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
```

- [ ] **Step 3: Resolve + build (slow — Metal kernels)**

Run: `swift package resolve`
Expected: resolves mlx-swift-examples ~1.18.2, mlx-swift, swift-transformers.

Run: `swift build`
Expected: `Build complete!` (first build is slow; this only adds deps, no new code yet).

- [ ] **Step 4: Commit**

```bash
git add Package.swift Package.resolved
git commit -m "build(mlx): add mlx-swift-examples dependency (MLXLLM, MLXLMCommon)"
```

---

## Task 3: MLXLLMService

The backend. MLX calls isolated here. Build-verified; generation is on-device smoke-tested.

**Files:**
- Create: `Core/MLXLLMService.swift`
- Modify: `Core/LLMServiceFactory.swift`

- [ ] **Step 1: Write the service**

Create `Core/MLXLLMService.swift`. Model it on `AppleIntelligenceService`. The MLX
generation block is version-sensitive — Step 2 is a compile-and-fix pass to reconcile
with the resolved `MLXLMCommon` API.

```swift
import Foundation
import MLXLLM
import MLXLMCommon
import OSLog

/// On-device MLX inference backend. Loads a quantized model from the HuggingFace
/// Hub (cached after first download) and reuses a single ModelContainer.
actor MLXLLMService: LLMService {
    static let shared = MLXLLMService()

    private var container: ModelContainer?
    private var loadedModelID: String?

    nonisolated var isAvailable: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    nonisolated var availabilityDescription: String {
        isAvailable ? "MLX ready (Apple Silicon)" : "MLX requires Apple Silicon"
    }

    private var currentModelID: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.mlxModelID)
            ?? "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
    }

    func handleOpenAIHTTPStatus(_ statusCode: Int, data: Data) throws {
        // Not network/OpenAI-based; nothing to validate.
    }

    func correct(text: String, promptType: PromptType, language: String) async throws -> CorrectionResult {
        let lang = language.isEmpty
            ? LanguageDetector.detect(text: text, fallbackLanguage: resolvedLanguage)
            : language
        let engine = PromptEngine(language: lang, style: await resolveStyle())
        let prompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)
        let corrected = try await generate(prompt)
        let validated = validateCorrection(original: text, corrected: corrected, isFluency: promptType.isFluency)
        return CorrectionResult(
            original: text, corrected: validated,
            modelID: currentModelID, confidence: Constants.defaultConfidence, promptType: promptType.label
        )
    }

    func correctFluency(text: String) async throws -> CorrectionResult {
        try await correct(text: text, promptType: .fluency, language: "")
    }

    func explain(original: String, corrected: String) async throws -> String {
        let lang = LanguageDetector.detect(text: corrected, fallbackLanguage: resolvedLanguage)
        let engine = PromptEngine(language: lang)
        let prompt = engine.buildExplainPrompt(original: original, corrected: corrected, customInstruction: nil)
        return try await generate(prompt)
    }

    func streamCorrect(text: String, promptType: PromptType) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let full = try await self.correct(text: text, promptType: promptType, language: "")
                    continuation.yield(full.corrected)
                    continuation.finish()
                } catch {
                    guard !Task.isCancelled else { return }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - MLX generation (reconcile with MLXLMCommon 1.18.2 in Step 2)

    private func loadContainerIfNeeded() async throws -> ModelContainer {
        let id = currentModelID
        if let container, loadedModelID == id { return container }
        do {
            let config = ModelConfiguration(id: id)
            let loaded = try await LLMModelFactory.shared.loadContainer(configuration: config) { progress in
                Logger.infra.info("MLX model load: \(progress.fractionCompleted)")
            }
            container = loaded
            loadedModelID = id
            return loaded
        } catch {
            Logger.infra.error("MLX load failed: \(error.localizedDescription)")
            throw CorrectionError.modelDownloadFailed(url: URL(string: "https://huggingface.co/\(id)")!)
        }
    }

    private func generate(_ prompt: String) async throws -> String {
        guard isAvailable else { throw CorrectionError.modelNotLoaded }
        let container = try await loadContainerIfNeeded()
        let result: String = try await container.perform { context in
            let input = try await context.processor.prepare(input: UserInput(prompt: prompt))
            let generateResult = try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(temperature: 0.3),
                context: context
            ) { _ in .more }
            return generateResult.output
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 2: Build and reconcile the MLX API**

Run: `swift build`
Expected: it MAY fail on the generation block (symbol/signature drift in
`UserInput` / `GenerateParameters` / `generate` / `ModelContainer.perform` /
`generateResult.output`). Fix against the resolved headers:
`grep -r "func generate" ~/.../checkouts/mlx-swift-examples/Libraries/MLXLMCommon`
and the `UserInput` / `ModelContext` definitions. Iterate until `Build complete!`.
Keep all fixes inside `generate`/`loadContainerIfNeeded` — do not change the public surface.

- [ ] **Step 3: Wire the factory to the real service**

In `Core/LLMServiceFactory.swift`, replace the temporary `.mlx` stub branch from Task 1:
```swift
        case .mlx:
            if MLXLLMService.shared.isAvailable {
                return MLXLLMService.shared
            }
            Logger.infra.warning("MLX requires Apple Silicon, falling back to .stub")
            return StubLLMService.shared
```

- [ ] **Step 4: Build + tests**

Run: `swift build` → Expected: `Build complete!`
Run: `swift test` → Expected: all pass (plumbing tests still green; no new unit tests for inference).

- [ ] **Step 5: Commit**

```bash
git add Core/MLXLLMService.swift Core/LLMServiceFactory.swift
git commit -m "feat(mlx): MLXLLMService — on-device MLX correction backend"
```

---

## Task 4: Settings polish (model field + progress)

Make the MLX model id editable and surface first-load progress.

**Files:**
- Modify: `UI/ServiceStep.swift` (and/or `UI/ModelsTab.swift`)

- [ ] **Step 1: Confirm the model-id field**

Ensure the `.mlx` branch added in Task 1 Step 8 binds a text field to
`prefs.mlxModel` with placeholder `mlx-community/Qwen2.5-1.5B-Instruct-4bit` and a
hint: "HuggingFace repo id of a quantized MLX model (mlx-community/*)." Match the
visual pattern of the ollama/openRouter model fields.

- [ ] **Step 2: Build**

Run: `swift build` → Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(mlx): MLX model-id field in engine settings"
```

---

## Task 5: Verification

- [ ] **Step 1: Full suite**

Run: `swift test` → Expected: all pass, 0 failures.
Run: `swift build` → Expected: `Build complete!`

- [ ] **Step 2: On-device smoke test (user — record results)**

On an Apple Silicon Mac, launch the app:
- Settings → engine → MLX; set model id to `mlx-community/Qwen2.5-1.5B-Instruct-4bit`.
- Trigger a grammar correction → first run downloads the model (watch progress) →
  output is a sane correction in the input language.
- Second correction is fast (container cached).
- Trigger a fluency correction → sane rewrite.
- Change the model id → next correction reloads.
- Enter a bogus repo id → graceful error, no crash, no hang.

- [ ] **Step 3: Final commit (if smoke-test fixes were needed)**

```bash
git add -A
git commit -m "fix(mlx): on-device smoke verification fixes"
```

---

## Notes for the implementer

- Run every command from `core/`.
- Task 3 Step 2 is the crux: the MLXLMCommon generation API will likely need
  reconciliation. Budget time for slow Metal builds between fixes.
- Do not commit a submodule-pointer bump in the outer `Wren` repo until the user
  has smoke-tested on-device.
- If `swift build` clean times become painful, build once and rely on incremental
  builds; only the first MLX build compiles the Metal kernels.
