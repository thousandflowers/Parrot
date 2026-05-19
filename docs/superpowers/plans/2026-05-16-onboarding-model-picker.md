# Onboarding Model Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aggiungere un pulsante-menu nel passo "Modello AI" dell'onboarding che mostra il modello consigliato pre-selezionato (rilevato dall'hardware) e permette di sceglierne un altro da un popup nativo.

**Architecture:** Si crea `Infra/ModelCatalog.swift` come fonte unica dei modelli disponibili (enum namespace con array statico). `ModelRecommendation` riceve due nuovi campi (`sizeLabel`, `isOnboardingCandidate`) con default value per non rompere i call-site esistenti. `ModelManager.recommendedDefaultModel()` viene ridotto a 5 righe che delegano a `ModelCatalog`. `OnboardingView` carica i modelli candidati dal catalogo e mostra un `Menu` SwiftUI con bordo e chevron.

**Tech Stack:** Swift 5.10, SwiftUI, XCTest

---

## File map

| File | Azione |
|---|---|
| `Infra/ModelManager.swift` | Modifica — aggiungi `sizeLabel` e `isOnboardingCandidate` a `ModelRecommendation`; semplifica `recommendedDefaultModel()` |
| `Infra/ModelCatalog.swift` | Crea — catalogo statico e funzione `recommended(ramGB:language:)` |
| `UI/OnboardingView.swift` | Modifica — aggiungi `availableModels` state, carica da catalogo, sostituisci testo statico con picker button |
| `Tests/Tests.swift` | Modifica — aggiungi `ModelCatalogTests` |

---

## Task 1: Estendi `ModelRecommendation` con `sizeLabel` e `isOnboardingCandidate`

**Files:**
- Modify: `Infra/ModelManager.swift` (struct `ModelRecommendation`, righe 5-13)

- [ ] **Step 1: Scrivi il test che verifica i nuovi campi**

Aggiungi alla fine di `Tests/Tests.swift`, prima della chiusura del file:

```swift
final class ModelCatalogTests: XCTestCase {
    func testModelRecommendation_hasSizeLabel() {
        let rec = ModelRecommendation(
            id: "test-model",
            name: "Test Model",
            reason: "Test reason",
            sizeLabel: "~2 GB",
            ramRequired: 4,
            url: URL(string: "https://example.com/model.gguf")!,
            expectedSHA256: nil,
            isOnboardingCandidate: true
        )
        XCTAssertEqual(rec.sizeLabel, "~2 GB")
        XCTAssertTrue(rec.isOnboardingCandidate)
    }
}
```

- [ ] **Step 2: Esegui il test per verificare che fallisca**

```bash
swift test --filter ModelCatalogTests 2>&1 | tail -20
```

Atteso: errore di compilazione — `sizeLabel` e `isOnboardingCandidate` non esistono.

- [ ] **Step 3: Aggiungi i campi a `ModelRecommendation` in `Infra/ModelManager.swift`**

Sostituisci la struct (righe 5-13):

```swift
struct ModelRecommendation: Sendable {
    let id: String
    let name: String
    let reason: String
    let sizeLabel: String = ""
    let ramRequired: Int
    let url: URL
    let expectedSHA256: String?
    var warning: String?
    let isOnboardingCandidate: Bool = true
}
```

I default value (`""` e `true`) garantiscono che i call-site esistenti in `recommendedDefaultModel()` continuino a compilare senza modifiche.

- [ ] **Step 4: Esegui il test per verificare che passi**

```bash
swift test --filter ModelCatalogTests 2>&1 | tail -20
```

Atteso: `ModelCatalogTests.testModelRecommendation_hasSizeLabel` PASS.

- [ ] **Step 5: Verifica che il resto della suite sia ancora verde**

```bash
swift test 2>&1 | tail -10
```

Atteso: `Build complete!` + tutti i test esistenti PASS.

- [ ] **Step 6: Commit**

```bash
git add Infra/ModelManager.swift Tests/Tests.swift
git commit -m "feat: add sizeLabel and isOnboardingCandidate to ModelRecommendation"
```

---

## Task 2: Crea `Infra/ModelCatalog.swift`

**Files:**
- Create: `Infra/ModelCatalog.swift`
- Modify: `Tests/Tests.swift`

- [ ] **Step 1: Aggiungi i test del catalogo a `Tests/Tests.swift`**

Aggiungi dentro `final class ModelCatalogTests` dopo il test esistente:

```swift
    func testOnboardingCandidates_hasThreeModels() {
        XCTAssertEqual(ModelCatalog.onboardingCandidates.count, 3)
    }

    func testRecommended_16GBRAMEnglish_returnsGemmaE4B() {
        UserDefaults.standard.removeObject(forKey: "lightweightMode")
        let rec = ModelCatalog.recommended(ramGB: 16, language: "en")
        XCTAssertEqual(rec.id, "gemma-4-E4B-it-q4_k_m")
    }

    func testRecommended_8GBRAMEnglish_returnsGemmaE2B() {
        UserDefaults.standard.removeObject(forKey: "lightweightMode")
        let rec = ModelCatalog.recommended(ramGB: 8, language: "en")
        XCTAssertEqual(rec.id, "gemma-4-E2B-it-q4_k_m")
    }

    func testRecommended_chineseLanguage_returnsQwen() {
        UserDefaults.standard.removeObject(forKey: "lightweightMode")
        let rec = ModelCatalog.recommended(ramGB: 16, language: "zh")
        XCTAssertEqual(rec.id, "qwen2.5-1.5b-instruct-q4_k_m")
    }

    func testAllModels_haveNonEmptySizeLabel() {
        for model in ModelCatalog.all {
            XCTAssertFalse(model.sizeLabel.isEmpty, "\(model.id) missing sizeLabel")
        }
    }

    func testAllModels_haveValidURLs() {
        for model in ModelCatalog.all {
            XCTAssertNotNil(model.url.host, "\(model.id) has invalid URL")
        }
    }
```

- [ ] **Step 2: Esegui per verificare che i nuovi test falliscano**

```bash
swift test --filter ModelCatalogTests 2>&1 | tail -20
```

Atteso: errore di compilazione — `ModelCatalog` non esiste.

- [ ] **Step 3: Crea `Infra/ModelCatalog.swift`**

```swift
import Foundation

enum ModelCatalog {
    static let all: [ModelRecommendation] = [
        ModelRecommendation(
            id: "qwen2.5-1.5b-instruct-q4_k_m",
            name: "Qwen 2.5 1.5B",
            reason: "Minimo consumo RAM — ideale per testi brevi e lingua cinese",
            sizeLabel: "~1.3 GB",
            ramRequired: 2,
            url: URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!,
            expectedSHA256: nil,
            isOnboardingCandidate: true
        ),
        ModelRecommendation(
            id: "gemma-4-E2B-it-q4_k_m",
            name: "Gemma 4 E2B IT (5B)",
            reason: "Buona qualità per lingue occidentali — Mac con meno di 16 GB",
            sizeLabel: "~2.5 GB",
            ramRequired: 4,
            url: URL(string: "https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf")!,
            expectedSHA256: nil,
            isOnboardingCandidate: true
        ),
        ModelRecommendation(
            id: "gemma-4-E4B-it-q4_k_m",
            name: "Gemma 4 E4B IT (8B)",
            reason: "Massima qualità per lingue occidentali — richiede Mac con 16 GB RAM o più",
            sizeLabel: "~4 GB",
            ramRequired: 6,
            url: URL(string: "https://huggingface.co/ggml-org/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf")!,
            expectedSHA256: nil,
            isOnboardingCandidate: true
        ),
    ]

    static var onboardingCandidates: [ModelRecommendation] {
        all.filter { $0.isOnboardingCandidate }
    }

    static func recommended(ramGB: Int, language: String) -> ModelRecommendation {
        let chineseLanguages = ["zh", "zh-Hans", "zh-Hant", "zh-HK"]
        if UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.lightweightMode)
            || chineseLanguages.contains(language) {
            return all.first { $0.id == "qwen2.5-1.5b-instruct-q4_k_m" }!
        }
        return ramGB >= 16
            ? all.first { $0.id == "gemma-4-E4B-it-q4_k_m" }!
            : all.first { $0.id == "gemma-4-E2B-it-q4_k_m" }!
    }
}
```

- [ ] **Step 4: Esegui i test del catalogo**

```bash
swift test --filter ModelCatalogTests 2>&1 | tail -20
```

Atteso: tutti e 7 i test PASS.

- [ ] **Step 5: Commit**

```bash
git add Infra/ModelCatalog.swift Tests/Tests.swift
git commit -m "feat: add ModelCatalog with 3 onboarding models and recommended() logic"
```

---

## Task 3: Semplifica `ModelManager.recommendedDefaultModel()`

**Files:**
- Modify: `Infra/ModelManager.swift` (funzione `recommendedDefaultModel`, righe 55-114)

- [ ] **Step 1: Sostituisci l'implementazione di `recommendedDefaultModel()`**

In `Infra/ModelManager.swift`, sostituisci l'intera funzione `recommendedDefaultModel()` (da `func recommendedDefaultModel()` fino alla chiusura `}` che termina la logica dei modelli, righe 55-114) con:

```swift
func recommendedDefaultModel() -> ModelRecommendation? {
    let lang = Locale.preferredLanguages.first
        .flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? "en"
    var rec = ModelCatalog.recommended(ramGB: getSystemRAM(), language: lang)
    if getSystemRAM() < 12 && rec.id == "gemma-4-E2B-it-q4_k_m" {
        rec.warning = "Questo modello richiede ~3.5 GB RAM. Chiudi altre app per migliori prestazioni."
    }
    return rec
}
```

Rimuovi anche la funzione helper privata `makeRec` che era nidificata dentro `recommendedDefaultModel()` — viene eliminata insieme alla funzione originale.

- [ ] **Step 2: Verifica che il build sia pulito**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Atteso: `Build complete!` senza errori.

- [ ] **Step 3: Esegui tutti i test**

```bash
swift test 2>&1 | tail -10
```

Atteso: tutti i test PASS.

- [ ] **Step 4: Commit**

```bash
git add Infra/ModelManager.swift
git commit -m "refactor: ModelManager.recommendedDefaultModel() delegates to ModelCatalog"
```

---

## Task 4: Aggiorna `OnboardingView` con il picker button

**Files:**
- Modify: `UI/OnboardingView.swift`

- [ ] **Step 1: Aggiungi lo state `availableModels` e popolalo nel `.task`**

In `UI/OnboardingView.swift`, aggiungi la property `@State` dopo `selectedModel`:

```swift
@State private var availableModels: [ModelRecommendation] = []
```

Nel blocco `.task { }` esistente (righe 37-41), aggiungi una riga dopo `selectedModel = ...`:

```swift
.task {
    accessibilityGranted = PreferencesStore.probeAccessibility()
    selectedModel = await ModelManager.shared.recommendedDefaultModel()
    availableModels = ModelCatalog.onboardingCandidates
    llamaServerReady = ModelManager.shared.resolvedLlamaServerURL() != nil
}
```

- [ ] **Step 2: Aggiungi la computed property `modelPickerButton`**

Aggiungi questa computed property dentro `OnboardingView`, prima di `// MARK: - Step 2: Model Download`:

```swift
// MARK: - Model Picker Button

private var modelPickerButton: some View {
    Menu {
        ForEach(availableModels, id: \.id) { model in
            Button {
                selectedModel = model
                downloadComplete = false
                downloadError = nil
            } label: {
                Text("\(model.name)  \(model.sizeLabel)")
            }
        }
    } label: {
        HStack(spacing: 6) {
            Text(selectedModel?.name ?? "Seleziona modello")
                .font(.body.weight(.medium))
            Image(systemName: "chevron.down")
                .imageScale(.small)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
        )
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
}
```

- [ ] **Step 3: Sostituisci il blocco statico `if let model = selectedModel` in `modelDownloadStep`**

Dentro `var modelDownloadStep: some View`, il blocco che mostra nome e reason (attualmente righe 145-151):

```swift
if let model = selectedModel {
    Text("\(model.name)")
        .font(.body.weight(.medium))
    Text(model.reason)
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

Sostituiscilo con:

```swift
modelPickerButton

if let model = selectedModel {
    Text(model.reason)
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 8)
    Text("\(model.sizeLabel) · min. \(model.ramRequired) GB RAM")
        .font(.caption2)
        .foregroundStyle(.tertiary)
}
```

- [ ] **Step 4: Verifica build pulito**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Atteso: `Build complete!` senza errori.

- [ ] **Step 5: Pacchetta l'app e testala manualmente**

```bash
./build-app.sh release && open Parrot.app
```

Verifica:
- Step "Modello AI" mostra il pulsante con nome del modello consigliato + bordo + chevron ▾
- Cliccando il pulsante si apre un popup con i 3 modelli
- Scegliendo un modello diverso il pulsante si aggiorna con il nuovo nome
- Il reason e la dimensione sotto si aggiornano di conseguenza
- "Scarica e continua" scarica il modello selezionato (non quello default)
- Se si era già scaricato e si cambia modello, il bottone torna a "Scarica e continua"

- [ ] **Step 6: Commit finale**

```bash
git add UI/OnboardingView.swift
git commit -m "feat: model picker button in onboarding — smart default + user override"
```
