# Fix 7 Bug Parrot — Piano di Lavoro

## TL;DR

> **Quick Summary**: Fix 7 bug trovati nel QA testing di Parrot: 1 critico (modelli off-screen), 2 alti (accessibilità MenuBar + elementi AX fantasma), 3 medi, 1 basso. TDD con test automatici Swift Testing.
>
> **Deliverables**:
> - ModelsTab: modelli visibili, scroll corretto, HStack duplicato rimosso
> - MenuBarView: elementi accessibili via AX
> - SettingsView: niente più elementi AX 0×0
> - Picker Servizio: binding corretto con `serviceType`
> - Checkbox "tempo reale": toggle funzionante
> - AppDelegate: alert permessi non blocca se sistema ha accessibilità
> - FloatingEditor: pulsanti azione nel messaggio errore AI
>
> **Estimated Effort**: Short (2h)
> **Parallel Execution**: YES — 2 waves
> **Critical Path**: T1 → T3 → T4

---

## Context

### Original Request
Fix dei 7 bug trovati durante il QA testing completo di Parrot (build Release, eseguito con macos-ui automation).

### QA Results Summary
Vedi report completo nella sessione precedente. I bug coprono: layout SwiftUI, accessibilità AX, binding @Bindable, logica condizionale, UX error messaging.

### Metis Review
Metis non disponibile (auth error). Analisi autonoma eseguita sui seguenti punti:
- **Scope**: Solo i 7 bug elencati. Nessun refactoring strutturale. Nessuna nuova feature.
- **Guardrails**: Non toccare Core/LLMService.swift, PromptEngine.swift, o la logica di business. Solo UI e binding.
- **Assunzioni validate**: Il binding `@Bindable var prefs` funziona ma potrebbe avere un problema con `Picker` che usa `.tag()` su un enum.

---

## Work Objectives

### Core Objective
Riparare tutti i 7 bug mantenendo il comportamento esistente invariato, con test di regressione TDD.

### Definition of Done
- [ ] `swift test` → tutti i test esistenti + nuovi PASS
- [ ] `swift build` → 0 warning
- [ ] Verifica manuale: Modelli tab mostra Phi-3.5 Mini e Gemma 4 E2B IT visibili
- [ ] Verifica AX: nessun elemento 0×0 nei tab Settings
- [ ] Verifica AX: MenuBar dropdown accessibile

### Must Have
- Fix layout ModelsTab (modelli off-screen)
- Fix duplicato HStack in ModelsTab
- Accessibilità MenuBarExtra
- Rimozione elementi AX fantasma
- Binding picker Servizio
- Checkbox reattivo
- UX migliorata per errore AI

### Must NOT Have (Guardrails)
- NON modificare Core/ servizi LLM
- NON modificare PromptEngine
- NON cambiare architettura @Bindable → @Observable (solo fix binding)
- NON aggiungere nuove feature
- NON refactoring massivo

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: YES (Swift Testing, 60+ test esistenti)
- **Automated tests**: TDD (Red-Green-Refactor)
- **Framework**: Swift Testing (`import Testing`)
- **Pattern**: Ogni task = test FAIL → fix → test PASS

### QA Policy
Ogni task include Agent-Executed QA Scenarios. Evidence in `.sisyphus/evidence/task-{N}-*.txt`.

- **Frontend/SwiftUI**: macos-ui (AX inspection + coordinate clicks + screenshot)
- **API/Logic**: `swift test` con output capture
- **Build**: `swift build` verifica 0 warning

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (indipendenti — 5 task, MAX PARALLEL):
├── T1: Fix layout ModelsTab (modelli off-screen + HStack duplicato)
├── T2: Fix accessibilità MenuBarExtra
├── T3: Rimuovi elementi AX fantasma (0×0)
├── T4: Fix binding picker Servizio
├── T5: Fix checkbox "Controllo in tempo reale"

Wave 2 (dopo Wave 1 — 2 task, PARALLEL):
├── T6: Fix alert permessi accessibilità
├── T7: Migliora UX messaggio errore AI
```

### Critical Path
```
T1 → T3 → (nessuna dipendenza bloccante per Wave 2)
```

---

## TODOs

### Wave 1 (PARALLEL — 5 task indipendenti)

---

### T1 [CRITICAL] Fix ModelsTab — Modelli Off-Screen + HStack Duplicato

**File**: `UI/SettingsView.swift` (ModelsTab, ModelRow, ExternalModelRow)

**Problema Root**: Il `List` in ModelsTab non calcola correttamente l'altezza del contenuto per tutti i modelli. Gli ultimi 2 (Phi-3.5 Mini, Gemma 4 E2B IT) sono a y=982, fuori dal viewport scroll (y=926). Inoltre, c'è un HStack duplicato alle linee 148-161 e 165-178.

**TDD Steps**:
1. **RED**: Scrivi test `testModelsTab_allModelsVisible()` — crea una `ModelsTab` con dati mock, verifica che tutti i modelli abbiano `frame.height > 0` e `frame.minY < scrollContentHeight`
2. **GREEN**: Fix — probabilmente il `VStack(alignment: .leading, spacing: 0)` contiene un doppio header che consuma spazio. Rimuovere il duplicato HStack (linee 165-178). Aggiungere `.frame(minHeight:)` o usare `ScrollView` invece di `List` se necessario.
3. **REFACTOR**: Estrarre l'header server status in una sub-view per evitare duplicazione futura.

**QA Scenario**:
```
Azione: Premi CMD+, → clicca tab "Modelli" → scroll fino in fondo
Atteso: Phi-3.5 Mini e Gemma 4 E2B IT visibili con pulsante "Scarica"
Verifica: macos-ui find_elements_in_app → AX position.y < 926 per tutti i modelli
```

**Files to change**: `UI/SettingsView.swift`

---

### T2 [HIGH] Fix Accessibilità MenuBarExtra Dropdown

**File**: `ParrotApp.swift`, `UI/MenuBarView.swift`

**Problema Root**: Il `MenuBarExtra` di SwiftUI non espone automaticamente i suoi elementi all'albero AX. Gli elementi del dropdown sono figli di SystemUIServer, non del processo app.

**TDD Steps**:
1. **RED**: Scrivi test `testMenuBarView_hasAccessibilityLabels()` — verifica che ogni elemento interattivo abbia `.accessibilityLabel()` e `.accessibilityHint()` non nil
2. **GREEN**: Aggiungi modificatori `.accessibilityLabel()`, `.accessibilityHint()`, `.accessibilityAddTraits()` a ogni elemento interattivo in `MenuBarView`:
   - Toggle "Controllo Automatico" → `.accessibilityLabel("Controllo automatico")`
   - Button "Controlla Grammatica" → `.accessibilityLabel("Controlla grammatica")`
   - Button "Analizza Tono" → `.accessibilityLabel("Analizza tono")`
   - Button "Editor Libero" → `.accessibilityLabel("Apri editor libero")`
   - Button "Impostazioni" → `.accessibilityLabel("Apri impostazioni")`
   - Button "Esci" → `.accessibilityLabel("Esci da Parrot")`
3. Aggiungi `.accessibilityElement(children: .contain)` al `VStack` principale
4. **REFACTOR**: Nessuno necessario

**QA Scenario**:
```
Azione: Apri il dropdown del MenuBarExtra (click icona barra menu)
Esegui: macos-ui find_elements annotating AXLabels
Atteso: Ogni bottone ha una label accessibile
```

**Files to change**: `UI/MenuBarView.swift`

---

### T3 [HIGH] Rimuovi Elementi AX Fantasma (0×0)

**File**: `UI/SettingsView.swift` (tutti i tab)

**Problema Root**: I componenti interni dello scroll (track, thumb, frecce) di SwiftUI `ScrollView`/`List` trapelano nell'albero AX come AXButton con size (0, 0). Questo è un comportamento noto di SwiftUI su macOS.

**TDD Steps**:
1. **RED**: Scrivi test `testSettingsTabs_noZeroSizeAXElements()` — verifica che nessun AXButton abbia `width: 0 AND height: 0` nei tab Generale, Avanzate (quelli con ScrollView/Form)
2. **GREEN**: Aggiungi `.accessibilityHidden(true)` agli `ScrollView` e `List` wrapper quando contengono solo sub-elementi che sono già accessibili. Oppure usa l'approccio `NSView` con `setAccessibilityElement(false)` sugli scroll interni.
3. In alternativa: avvolgi ogni contenuto di tab in un `Group` con `.accessibilityElement(children: .combine)` per impedire la propagazione degli elementi interni.
4. **REFACTOR**: Creare un ViewModifier riutilizzabile `.cleanAccessibilityTree()` da applicare ai container con scroll.

**QA Scenario**:
```
Azione: CMD+, → naviga tutti i 6 tab uno per uno
Esegui: macos-ui find_elements_in_app("Parrot")
Atteso: Nessun elemento con size=(0,0) nei risultati
```

**Files to change**: `UI/SettingsView.swift`

---

### T4 [MEDIUM] Fix Binding Picker Servizio

**File**: `UI/SettingsView.swift` (GeneralTab, linee 59-130)

**Problema Root**: Il `Picker("Servizio", selection: $prefs.serviceType)` potrebbe non propagare il cambiamento a `PreferencesStore` se il binding non è configurato correttamente. Possibile causa: `@Bindable` su un `@Observable` class che ha `serviceType` come computed property invece che stored.

**TDD Steps**:
1. **RED**: Scrivi test `testServiceTypePicker_changesPreferencesStore()` — simula la selezione di un nuovo valore e verifica che `prefs.serviceType` sia aggiornato
2. **GREEN**: Verificare che `PreferencesStore.serviceType` sia una stored property (var, non computed). Se è computed, convertire in stored con `didSet` per UserDefaults sync.
3. Se il problema è nel `.tag()`: verificare che `ServiceType` sia `Hashable` e che il `.tag()` corrisponda esattamente al tipo.
4. **REFACTOR**: Nessuno necessario

**QA Scenario**:
```
Azione: CMD+, → clicca picker "Servizio" → seleziona "Stub (test)" → chiudi e riapri Impostazioni
Atteso: Il picker mostra "Stub (test)"
```

**Files to change**: `UI/SettingsView.swift`, `Infra/PreferencesStore.swift` (solo se serviceType è computata)

---

### T5 [MEDIUM] Fix Checkbox "Controllo in Tempo Reale"

**File**: `UI/SettingsView.swift` (GeneralTab, ~linea 120)

**Problema Root**: La checkbox "Controllo in tempo reale" non cambiava stato con i click via coordinate. Due possibilità: (a) problema di coordinate nel test automation, (b) il Toggle non è correttamente bindato.

**TDD Steps**:
1. **RED**: Scrivi test `testRealtimeToggle_changesValue()` — verifica che il toggle cambi il valore di `prefs.realtimeEnabled` (o la chiave UserDefaults corrispondente)
2. **GREEN**: Verificare che il Toggle sia bindato a `$prefs.realtimeEnabled` (o `UserDefaults.standard.bool(forKey: "realtimeEnabled")`). Se usa `@AppStorage`, assicurarsi che la chiave sia corretta.
3. Controllare che `realtimeEnabled` esista in `PreferencesStore` come `@Observable` property.
4. **REFACTOR**: Nessuno necessario

**QA Scenario**:
```
Azione: CMD+, → clicca checkbox "Controllo in tempo reale" 2 volte
Esegui: macos-ui find_elements_in_app → verifica AXCheckBox value
Atteso: value cambia tra 0 e 1 ad ogni click
```

**Files to change**: `UI/SettingsView.swift`, `Infra/PreferencesStore.swift` (verifica)

---

### Wave 2 (PARALLEL — dopo Wave 1)

---

### T6 [MEDIUM] Fix Alert Permessi Accessibilità

**File**: `App/AppDelegate.swift` (checkAccessibilityPermissions, linee 62-78)

**Problema Root**: L'alert appare sempre al primo avvio perché `AXIsProcessTrustedWithOptions` restituisce false per app non firmate, anche quando il sistema ha l'accessibilità abilitata globalmente.

**TDD Steps**:
1. **RED**: Scrivi test `testAccessibilityAlert_onlyShowsWhenNotTrusted()` — mock `AXIsProcessTrustedWithOptions` per restituire true, verifica che l'alert non venga mostrato
2. **GREEN**: Aggiungere un check aggiuntivo: dopo `AXIsProcessTrustedWithOptions`, verificare anche se il sistema ha accessibilità enabled tramite `AXIsProcessTrusted()` (senza options — senza prompt). Se `AXIsProcessTrusted()` è true ma `AXIsProcessTrustedWithOptions` è false, mostrare un alert più soft o saltare.
3. Aggiungere un flag UserDefaults `hasAcknowledgedAccessibilityWarning` per non ripetere l'alert.
4. **REFACTOR**: Estrarre la logica in un metodo `shouldShowAccessibilityWarning() -> Bool`

**QA Scenario**:
```
Azione: Riavvia l'app con accessibilità di sistema abilitata
Atteso: Nessun alert (o un alert solo informativo, non bloccante)
```

**Files to change**: `App/AppDelegate.swift`

---

### T7 [LOW] Migliora UX Messaggio Errore AI

**File**: `UI/FloatingEditor.swift` (FloatingEditorView)

**Problema Root**: Il messaggio "Il motore AI non è ancora pronto. Attendi qualche secondo e riprova." non offre azioni all'utente.

**TDD Steps**:
1. **RED**: Scrivi test `testAIErrorMessage_hasActionButtons()` — verifica che la view di errore contenga almeno un pulsante d'azione
2. **GREEN**: Modificare la view dell'errore per includere:
   - Pulsante "Riprova" che ri-esegue il check
   - Pulsante "Usa Stub" che switcha temporaneamente a StubLLMService
   - (Opzionale) countdown automatico con retry dopo 3 secondi
3. La view corrente mostra l'errore come `Text(errorMessage)`. Convertire in una HStack/VStack con pulsanti.
4. **REFACTOR**: Estrarre la view errore in una sub-view `AIErrorView`

**QA Scenario**:
```
Azione: Apri Floating Editor (Cmd+Shift+F), scrivi testo, clicca "Controlla"
Atteso (se server fermo): Messaggio errore con pulsanti "Riprova" e "Usa Stub"
Clicca "Usa Stub": Il check riparte con StubLLMService
Atteso: Testo corretto appare nel pannello destro
```

**Files to change**: `UI/FloatingEditor.swift`
