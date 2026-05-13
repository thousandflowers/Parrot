# Audit Improvements — RefineClone

## TL;DR

> **Quick Summary**: Eseguire 5 migliorie derivate dall'audit tecnico (score 11/20 → target 15-16/20): token di colore, decomposizione god object, font dinamici, accessibility labels, standardizzazione pattern async.
>
> **Deliverables**:
> - Estensione `Color` con token semantici light/dark (sostituisce 15+ `.red/.green/.blue/.orange`)
> - `SettingsView.swift` decomposto: 6 file tab separati
> - `PreferencesStore.swift` decomposto: estratti `SeedDataProvider`, `PreferencesCache`
> - `OnboardingView.swift`: `.system(size:)` → `.font(.largeTitle/.title)`
> - `FloatingEditor.swift`: `.accessibilityLabel()` e `.accessibilityHint()` su tutti i pulsanti
> - Pattern Task standardizzato: `[weak self]` consistente, `do/catch` dove mancante
>
> **Estimated Effort**: Medium (3-4h)
> **Parallel Execution**: YES — 4 waves
> **Critical Path**: T1 → T2 → T4/T5 → T6

---

## Context

### Original Request
Eseguire tutte e 5 le migliorie raccomandate dall'audit tecnico di RefineClone in sequenza.

### Audit Baseline (11/20)
| # | Dimension | Score |
|---|---|---|
| 1 | Accessibility | 2/4 |
| 2 | Performance | 3/4 |
| 3 | Theming | 1/4 |
| 4 | Responsive Design | 3/4 |
| 5 | Anti-Patterns | 2/4 |

### Metis Review
Non disponibile. Gap analysis autonoma: guardrails applicati (no cambio semantica colori, no cambio comportamento, no design system completo).

---

## Work Objectives

### Core Objective
Portare il codice da 11/20 a 15-16/20 applicando 5 migliorie sequenziali.

### Definition of Done
- `swift test` → 67 test PASS
- `swift build` → 0 errori, 0 nuovi warning
- 0 colori hard-coded in `UI/`
- 0 `.system(size:)` in `OnboardingView`
- `.accessibilityLabel()` su ogni Button in `FloatingEditor`

### Must Have
- Token colore in `UI/DesignTokens.swift`
- `SettingsView` decomposto in 6 tab file
- `PreferencesStore` decomposto
- Font semantici in `OnboardingView`
- Accessibility labels su `FloatingEditor`
- Pattern Task standardizzato

### Must NOT Have
- NON cambiare semantica visiva dei colori
- NON cambiare comportamento app
- NON introdurre regressioni
- NON design system completo
- NON toccare logica business Core/

---

## Verification Strategy

### Test Decision
- **Infrastructure**: YES (67 test XCTest)
- **Nuovi test**: No (refactoring puro)
- **Verifica**: `swift test` + `swift build` per ogni task

### QA Policy
Agent-Executed QA per ogni task. Evidence in `.sisyphus/evidence/task-{N}-*.txt`.

---

## Execution Strategy

```
Wave 1 (Start Immediately):
├── T1: /colorize — Token di colore semantici

Wave 2 (After T1 — MAX PARALLEL):
├── T2: /distill — Decomposizione SettingsView
└── T3: /distill — Decomposizione PreferencesStore

Wave 3 (After T2,T3 — MAX PARALLEL):
├── T4: /typeset — Font dinamici OnboardingView
└── T5: /clarify — Accessibility labels FloatingEditor

Wave 4 (After ALL):
└── T6: /polish — Standardizzazione pattern Task
```

### Critical Path
T1 → T2 → T4/T5 → T6

---

## TODOs

### Wave 1 — Foundation

- [x] 1. /colorize — Creare token di colore semantici e sostituire 15+ hard-coded

  **What to do**:
  - Creare `UI/DesignTokens.swift` con estensione `Color`:
    - `Color.statusOk` (green in light, adattato in dark)
    - `Color.statusWarning` (orange in light, adattato in dark)
    - `Color.statusError` (red in light, adattato in dark)
    - `Color.statusInactive` (gray/secondary)
    - `Color.accentBrand` (blue in light, adattato in dark)
    - `Color.textPrimary` (mappa a `.primary`)
    - `Color.textSecondary` (mappa a `.secondary`)
  - Ogni token con supporto dark mode nativo via `Color(NSColor(...))`
  - Sostituire TUTTE le occorrenze in `UI/`:
    - `.foregroundColor(.green)` → `.foregroundColor(.statusOk)`
    - `.foregroundColor(.orange)` → `.foregroundColor(.statusWarning)`
    - `.foregroundColor(.red)` → `.foregroundColor(.statusError)`
    - `.foregroundColor(.blue)` → `.foregroundColor(.accentBrand)`
    - `Color.green` / `Color.red` in `.fill()` → token corrispondenti
    - `.foregroundColor(.primary)` → `.foregroundColor(.textPrimary)`
    - `.foregroundColor(.secondary)` → `.foregroundColor(.textSecondary)`

  **Must NOT do**:
  - NON cambiare la semantica: `.green` per "server attivo" deve rimanere verde
  - NON toccare colori in file `Core/` o `Infra/`
  - NON creare palette completa — solo i 7 token necessari

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
  - **Skills**: [`colorize`]

  **Parallelization**: Wave 1, Blocks T2-T6

  **References**:
  - `UI/SettingsView.swift:127` — `Color.green/.red` per stato server
  - `UI/MenuBarView.swift:25,33` — `.green`, `.orange`
  - `UI/OnboardingView.swift:83,99,123` — `.green`, `.orange`, `.blue`
  - `UI/SuggestionView.swift:54,96,99,102,115,161` — colori multipli
  - `UI/RealtimeIndicator.swift:91,96,105` — colori stato
  - Apple HIG Color: semantic colors in macOS

  **Acceptance Criteria**:
  - [ ] `grep -rn '\.red\|\.green\|\.blue\|\.orange' UI/` → 0 hard-coded
  - [ ] `swift build` → 0 errori
  - [ ] `swift test` → 67/67 passano
  - [ ] `UI/DesignTokens.swift` esiste con 7+ token

  **QA Scenarios**:
  ```
  Scenario: Token compilano e sostituiscono tutti i colori
    Tool: Bash
    Steps:
      1. swift build → deve compilare senza errori
      2. grep -rn "\.red\|\.green\|\.blue\|\.orange" UI/*.swift → 0 risultati
      3. grep -rn "\.statusOk\|\.statusWarning\|\.accentBrand\|\.textPrimary" UI/*.swift → risultati in >=3 file
    Expected Result: 0 hard-coded colors, token usati nei file UI
    Evidence: .sisyphus/evidence/task-1-colorize.txt

  Scenario: Nessuna regressione test
    Tool: Bash
    Steps:
      1. swift test 2>&1 | tail -3
    Expected Result: "Executed 67 tests, with 0 failures"
    Evidence: .sisyphus/evidence/task-1-test.txt
  ```

  **Commit**: YES (`refactor: add semantic color tokens`)


---

### Wave 2 — MAX PARALLEL (after T1)

- [x] 2. /distill — Decomporre SettingsView.swift (608 linee) in 6 file tab separati

  **What to do**:
  - Creare nuovi file in `UI/`:
    - `GeneralTab.swift` — estrarre `GeneralTab` struct (linee ~65-137)
    - `ModelsTab.swift` — estrarre `ModelsTab` struct + `ModelRow` + `ExternalModelRow` (linee ~139-580)
    - `PromptTab.swift` — estrarre `PromptTab` struct
    - `AppRulesTab.swift` — estrarre `AppRulesTab` struct
    - `ExclusionsTab.swift` — estrarre `ExclusionsTab` struct
    - `AdvancedTab.swift` — estrarre `AdvancedTab` struct (già indipendente)
  - Mantenere `SettingsView.swift` solo con la `TabView` shell e i binding (linee 1-63)
  - Ogni nuovo file importa `SwiftUI`. `@Bindable var prefs: PreferencesStore` preservato
  - Verificare che `Package.swift` non richieda modifiche (target path copre `UI/`)

  **Must NOT do**:
  - NON cambiare la logica di nessun tab
  - NON rompere `@Bindable var prefs` propagation
  - NON rimuovere `.accessibilityElement(children: .contain)` dai tab

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: [`distill`]
    - `distill`: Dominio specifico per decomporre e semplificare codice

  **Parallelization**:
  - **Can Run In Parallel**: YES (con T3)
  - **Parallel Group**: Wave 2
  - **Blocks**: T4, T5, T6
  - **Blocked By**: T1

  **References**:
  - `UI/SettingsView.swift` — file completo da decomporre
  - `UI/MenuBarView.swift` — esempio di view standalone ben strutturata
  - `Package.swift:10-23` — target configuration

  **Acceptance Criteria**:
  - [ ] `swift build` → 0 errori
  - [ ] `swift test` → 67/67 passano
  - [ ] `UI/GeneralTab.swift`, `UI/ModelsTab.swift`, etc. esistono
  - [ ] `UI/SettingsView.swift` < 80 linee

  **QA Scenarios**:
  ```
  Scenario: Compilazione dopo decomposizione
    Tool: Bash
    Steps:
      1. swift build 2>&1 | grep -E "(error|Build complete)"
      2. ls UI/GeneralTab.swift UI/ModelsTab.swift UI/PromptTab.swift UI/AppRulesTab.swift UI/ExclusionsTab.swift UI/AdvancedTab.swift
    Expected Result: "Build complete!" + 6 nuovi file esistono
    Evidence: .sisyphus/evidence/task-2-distill-settings.txt

  Scenario: Test passano dopo refactoring
    Tool: Bash
    Steps:
      1. swift test 2>&1 | tail -3
    Expected Result: 67 tests, 0 failures
    Evidence: .sisyphus/evidence/task-2-test.txt
  ```

  **Commit**: YES (`refactor: decompose SettingsView into 6 tab files`)

- [x] 3. /distill — Decomporre PreferencesStore.swift (449 linee) estraendo SeedDataProvider e PreferencesCache

  **What to do**:
  - Creare `Infra/SeedDataProvider.swift` con `seedDefaults()`, `seedPromptPresets()`, `seedSecurityExclusions()`
  - Creare `Infra/PreferencesCache.swift` con cache properties (`_cachedPrompts`, `_cachedAppRules`, `_cachedAccessibility`)
  - Mantenere `PreferencesStore.swift` con solo properties `@Observable` + delegation a SeedDataProvider e PreferencesCache
  - `PreferencesStore.init()` chiama `SeedDataProvider.seed(self)` e `PreferencesCache.shared`

  **Must NOT do**:
  - NON cambiare la logica di seeding o caching
  - NON rompere l'API pubblica di `PreferencesStore`
  - NON introdurre dipendenze circolari

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: [`distill`]

  **Parallelization**:
  - **Can Run In Parallel**: YES (con T2)
  - **Parallel Group**: Wave 2
  - **Blocks**: T6 (polish)
  - **Blocked By**: T1

  **References**:
  - `Infra/PreferencesStore.swift:28-43` — seedDefaults
  - `Infra/PreferencesStore.swift:45-67` — seedPromptPresets
  - `Infra/PreferencesStore.swift:81-84` — seedSecurityExclusions
  - `Infra/PreferencesStore.swift:10-20` — cache properties

  **Acceptance Criteria**:
  - [ ] `swift build` → 0 errori
  - [ ] `swift test` → 67/67 passano
  - [ ] `Infra/SeedDataProvider.swift` e `Infra/PreferencesCache.swift` esistono
  - [ ] `Infra/PreferencesStore.swift` < 200 linee

  **QA Scenarios**:
  ```
  Scenario: Compilazione + test dopo decomposizione PreferencesStore
    Tool: Bash
    Steps:
      1. swift build && swift test 2>&1 | tail -3
    Expected Result: "Executed 67 tests, with 0 failures"
    Evidence: .sisyphus/evidence/task-3-distill-prefs.txt
  ```

  **Commit**: YES (`refactor: extract SeedDataProvider and PreferencesCache from PreferencesStore`)


---

### Wave 3 — MAX PARALLEL (after T2, T3)

- [x] 4. /typeset — Sostituire font fissi in OnboardingView con semantic styles

  **What to do**:
  - `OnboardingView.swift:82`: `.font(.system(size: 64))` → `.font(.largeTitle)`
  - `OnboardingView.swift:98`: `.font(.system(size: 48))` → `.font(.title)`
  - `OnboardingView.swift:122`: `.font(.system(size: 48))` → `.font(.title)`
  - Verificare che il layout non si rompa con Dynamic Type attivo

  **Must NOT do**:
  - NON cambiare il layout visivo a default size
  - NON toccare altri file

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: [`typeset`]
    - `typeset`: Dominio specifico per scelte tipografiche

  **Parallelization**:
  - **Can Run In Parallel**: YES (con T5)
  - **Parallel Group**: Wave 3
  - **Blocks**: T6
  - **Blocked By**: T1

  **References**:
  - `UI/OnboardingView.swift:82` — `.system(size: 64)` icon emoji
  - `UI/OnboardingView.swift:98,122` — `.system(size: 48)` icon emoji

  **Acceptance Criteria**:
  - [ ] `grep -rn 'system(size:' UI/OnboardingView.swift` → 0 risultati
  - [ ] `swift build` → 0 errori
  - [ ] `swift test` → 67/67 passano

  **QA Scenarios**:
  ```
  Scenario: Font semantici compilano
    Tool: Bash
    Steps:
      1. grep -rn 'system(size:' UI/OnboardingView.swift
      2. swift build 2>&1 | grep "Build complete"
    Expected Result: 0 risultati grep + "Build complete!"
    Evidence: .sisyphus/evidence/task-4-typeset.txt
  ```

  **Commit**: YES (`refactor: use semantic font styles in OnboardingView for Dynamic Type`)

- [x] 5. /clarify — Aggiungere accessibility labels ai pulsanti FloatingEditor

  **What to do**:
  - `FloatingEditor.swift:145`: Button "Riprova" → `.accessibilityLabel("Riprova controllo")` + `.accessibilityHint("Riesegue il controllo grammaticale")`
  - `FloatingEditor.swift:148`: Button "Usa Stub" → `.accessibilityLabel("Usa servizio stub")` + `.accessibilityHint("Esegue il controllo con il servizio di test locale")`
  - `FloatingEditor.swift:155`: Button "Controlla" → `.accessibilityLabel("Controlla testo")` + `.accessibilityHint("Avvia il controllo grammaticale sul testo inserito")`
  - `FloatingEditor.swift:159`: Button "Copia" → `.accessibilityLabel("Copia testo corretto")` + `.accessibilityHint("Copia il testo corretto negli appunti")`
  - Aggiungere `.accessibilityLabel("Editor di testo")` al `TextEditor`
  - Aggiungere `.accessibilityLabel("Testo corretto")` alla sezione output

  **Must NOT do**:
  - NON cambiare il comportamento dei pulsanti
  - NON modificare layout

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: [`clarify`]
    - `clarify`: Dominio specifico per migliorare UX copy e labels

  **Parallelization**:
  - **Can Run In Parallel**: YES (con T4)
  - **Parallel Group**: Wave 3
  - **Blocks**: T6
  - **Blocked By**: T1

  **References**:
  - `UI/FloatingEditor.swift:140-166` — pulsanti nell'editor
  - `UI/MenuBarView.swift:66-90` — esempio di accessibility labels ben fatte

  **Acceptance Criteria**:
  - [ ] `grep -c 'accessibilityLabel' UI/FloatingEditor.swift` → >= 6
  - [ ] `swift build` → 0 errori
  - [ ] `swift test` → 67/67 passano

  **QA Scenarios**:
  ```
  Scenario: Accessibility labels presenti su tutti i pulsanti
    Tool: Bash
    Steps:
      1. grep -c 'accessibilityLabel' UI/FloatingEditor.swift
      2. grep -c 'accessibilityHint' UI/FloatingEditor.swift
    Expected Result: >=6 labels, >=4 hints
    Evidence: .sisyphus/evidence/task-5-clarify.txt
  ```

  **Commit**: YES (`a11y: add accessibility labels to FloatingEditor buttons`)


---

### Wave 4 — Polish Finale (after T4, T5)

- [x] 6. /polish — Standardizzare pattern Task async in UI/

  **What to do**:
  - Aggiungere `[weak self]` a TUTTI i `Task {` in classi/actor (FloatingEditorController, SuggestionPanelController, RealtimeIndicatorController) che catturano `self`. NON necessario per SwiftUI struct (SettingsView, OnboardingView, etc.) dove self e un value type
  - Aggiungere `do/catch` con `os_log(.error)` dove manca (SettingsView, SuggestionPanel, RealtimeIndicator)
  - Verificare che `defer { self?.isLoading = false }` sia presente nei Task di loading
  - Standardizzare: ogni `Task {` che modifica `@State` deve avere `@MainActor in`
  - Aggiungere `guard !Task.isCancelled else { return }` dove assente

  **Must NOT do**:
  - NON cambiare la logica di business
  - NON introdurre regressioni

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: [`polish`]
    - `polish`: Dominio specifico per quality pass finale

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 4 (finale)
  - **Blocks**: -
  - **Blocked By**: T1, T4, T5

  **References**:
  - `UI/SuggestionPanel.swift:170` — esempio corretto: `Task { [weak self] in`
  - `UI/FloatingEditor.swift:201` — esempio corretto: `Task { @MainActor in`
  - `UI/SettingsView.swift:224` — Task senza weak self (da fixare)
  - `UI/RealtimeIndicator.swift:17` — Task pattern da verificare
  - `UI/SuggestionPanel.swift:156` — Task senza weak self (da fixare)

  **Acceptance Criteria**:
  - [ ] `grep -rn 'Task {' UI/SuggestionPanel.swift UI/FloatingEditor.swift UI/RealtimeIndicator.swift | grep -v 'weak self'` → 0 Task che catturano self senza weak
  - [ ] `swift build` → 0 errori
  - [ ] `swift test` → 67/67 passano

  **QA Scenarios**:
  ```
  Scenario: Nessun Task senza weak self in UI
    Tool: Bash
    Steps:
      1. grep -rn 'Task {' UI/SuggestionPanel.swift UI/FloatingEditor.swift UI/RealtimeIndicator.swift | grep -v 'weak self'
    Expected Result: 0 risultati (o solo Task che non catturano self)
    Evidence: .sisyphus/evidence/task-6-polish.txt

  Scenario: Build + test passano
    Tool: Bash
    Steps:
      1. swift build && swift test 2>&1 | tail -3
    Expected Result: Build OK, 67 tests, 0 failures
    Evidence: .sisyphus/evidence/task-6-test.txt
  ```

  **Commit**: YES (`refactor: standardize async Task patterns in UI`)

---

## Final Verification Wave

- [x] F1. **Plan Compliance Audit** — `oracle`
  Verifica che tutti i "Must Have" siano implementati e tutti i "Must NOT Have" siano assenti. Controlla `grep` per colori hard-coded, `system(size:)`, file decomposti.

- [x] F2. **Build + Test** — `quick`
  `swift build && swift test`. Deve passare 67/67.

- [x] F3. **Re-audit Score** — `quick`
  Rilancia i check dell'audit originale: conta colori hard-coded, verifica font dinamici, controlla accessibility labels, verifica decomposizione. Stima il nuovo score.

---

## Commit Strategy

- **T1**: `refactor: add semantic color tokens, replace 15+ hardcoded colors`
- **T2**: `refactor: decompose SettingsView into 6 tab files`
- **T3**: `refactor: extract SeedDataProvider and PreferencesCache`
- **T4**: `refactor: use semantic font styles in OnboardingView`
- **T5**: `a11y: add accessibility labels to FloatingEditor buttons`
- **T6**: `refactor: standardize async Task patterns in UI`

---

## Success Criteria

### Verification Commands
```bash
swift build                 # Expected: Build complete!
swift test                  # Expected: 67 tests, 0 failures
grep -rn '\.red\|\.green\|\.blue\|\.orange' UI/  # Expected: 0 hard-coded
grep -rn 'system(size:' UI/OnboardingView.swift   # Expected: 0
grep -c 'accessibilityLabel' UI/FloatingEditor.swift  # Expected: >=6
```

### Final Checklist
- [ ] 67/67 test passano
- [ ] 0 hard-coded colori in UI/
- [ ] 0 font fissi in OnboardingView
- [ ] >=6 accessibility labels in FloatingEditor
- [ ] 0 Task senza [weak self] in UI/
- [ ] Score stimato ≥ 15/20
