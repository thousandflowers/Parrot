# Localization & Smart Correction Language — Design Spec

## Scope

Two independent but related features delivered together:

1. **UI Localization** — l'interfaccia dell'app segue la lingua di sistema del Mac
2. **Smart Correction Language** — la lingua usata per correggere/tradurre il testo viene rilevata automaticamente dal testo selezionato, con override manuale

---

## Part 1: UI Localization

### Goal
Tutte le stringhe visibili nell'interfaccia (pulsanti, menu, label, alert, messaggi di errore, onboarding) sono localizzate. macOS sceglie automaticamente la lingua in base alle preferenze di sistema. Fallback a inglese per lingue senza file di traduzione.

### Lingue supportate al lancio
| Codice | Lingua |
|--------|--------|
| `en` | English (base / development language) |
| `it` | Italiano |
| `zh-Hans` | 中文 (Cinese semplificato) |
| `hr` | Hrvatski (Croato) |
| `da` | Dansk (Danese) |
| `nb` | Norsk Bokmål (Norvegese) |
| `el` | Ελληνικά (Greco) |

### Architettura

**Package.swift**: aggiunta di `defaultLocalization: "en"` alla dichiarazione `Package` e di `resources: [.process("Resources/en.lproj"), ...]` per ogni lingua nel target.

**Stringhe**: ogni stringa hardcodata diventa `String(localized: "chiave.descrittiva")`. La chiave è in inglese e corrisponde al testo inglese di default. Esempio:
```swift
// prima
Text("Benvenuto in Parrot")
// dopo
Text(String(localized: "onboarding.welcome.title"))
```

**File per lingua**: `Resources/<codice>.lproj/Localizable.strings`. Formato standard Apple:
```
"onboarding.welcome.title" = "Welcome to Parrot";
```

**Scope delle stringhe**: solo stringhe UI visibili all'utente. Escluse:
- Stringhe nei test (`Tests/Tests.swift`)
- Chiavi UserDefaults e identificatori interni
- Testo nei prompt LLM (`PromptEngine.swift`) — quelli sono prompt tecnici, non UI
- Descrizioni delle regole grammaticali in `RuleBasedEngine.swift` — queste sono contenuto, non UI

### File da modificare (UI strings)
| File | Stringhe UI da localizzare |
|------|---------------------------|
| `UI/OnboardingView.swift` | ~8 (titoli step, pulsanti, label) |
| `UI/MenuBarView.swift` | ~6 (voci menu) |
| `UI/SuggestionView.swift` | ~5 (pulsanti azione) |
| `UI/FloatingEditor.swift` | ~3 (pulsanti editor) |
| `UI/GeneralTab.swift` | ~4 (label sezioni, picker) |
| `UI/ShortcutsTab.swift` | ~2 |
| `UI/AdvancedTab.swift` | ~2 |
| `UI/CustomRulesView.swift` | ~2 |
| `UI/ModelsTab.swift` | ~2 |
| `App/AppDelegate.swift` | ~3 (alert text) |
| `Infra/ModelCatalog.swift` | ~3 (reason dei modelli) |

Totale stimato: ~40 stringhe UI (le restanti ~22 sono in PromptEngine/RuleBasedEngine/Tests, escluse).

### Traduzioni
- **English + Italiano**: traduzione manuale (accuracy garantita)
- **ZH-Hans, HR, DA, NB, EL**: generazione AI inline durante l'implementazione (62 stringhe, qualità buona per testi UI brevi)

---

## Part 2: Smart Correction Language

### Goal
Quando l'utente corregge o traduce testo, la lingua di output viene rilevata automaticamente dal contenuto del testo selezionato usando Apple `NLLanguageRecognizer`. L'utente può comunque fissare una lingua manuale nelle Preferenze. La voce "Automatico" diventa il default per le nuove installazioni.

### Architettura

**`PreferencesStore.language`**: guadagna il valore sentinella `"auto"`. Il default per nuove installazioni diventa `"auto"` invece del locale di sistema.

**`TextCheckCoordinator.prepareCheck()`**: prima di costruire il prompt, risolve la lingua effettiva:
```swift
let resolvedLanguage: String
if storedLanguage == "auto" {
    resolvedLanguage = LanguageDetector.detect(text: selectedText, fallbackLanguage: Locale.current.language.languageCode?.identifier ?? "en")
} else {
    resolvedLanguage = storedLanguage
}
```
`LanguageDetector` esiste già in `Core/LanguageDetector.swift` e usa `NLLanguageRecognizer`.

**`UI/GeneralTab.swift`**: il `Picker("Lingua", ...)` riceve una prima voce:
```swift
Text("Automatico (rileva dal testo)").tag("auto")
```
Prima di tutte le altre lingue.

**Fallback**: testi troppo corti (<10 caratteri) o ambigui → `NLLanguageRecognizer` restituisce `nil` → si usa `Locale.current.language.languageCode` come fallback.

### Comportamento per utenti esistenti
`PreferencesStore.language` legge da UserDefaults con fallback a `localeDefault()`.

- **Nuove installazioni**: nessuna chiave in UserDefaults → `localeDefault()` viene modificato per ritornare `"auto"` invece del codice locale → lingua automatica attiva da subito.
- **Installazioni esistenti**: UserDefaults ha già un valore (es. `"it"`) → lo mantiene senza modifiche → nessuna regressione.

La modifica è una sola riga in `PreferencesStore.localeDefault()`:
```swift
// prima
return Locale.current.language.languageCode?.identifier ?? "it"
// dopo
return "auto"
```

---

---

## Part 3: Language-Universal Rule Engine

### Goal
Le funzionalità di correzione (grammatica, fluidità) devono funzionare per qualsiasi lingua. Le regole semplici e universali si applicano a tutti i testi indipendentemente dalla lingua; le regole specifiche (italiano, inglese) si applicano solo quando la lingua è quella.

### Stato attuale
`GrammarRule` ha `languages: Set<String>`. La doppio-spazio rule è taggata `["it", "en", "es", "fr", "de", "pt"]` — non si applica a cinese, danese, greco, croato ecc.

### Modifica: flag `isUniversal`

`GrammarRule` guadagna un campo:
```swift
let isUniversal: Bool  // default: false
```

`RuleBasedEngine.check()` cambia il filtro:
```swift
// prima
for (rule, regex) in compiledRules where rule.languages.contains(language)
// dopo
for (rule, regex) in compiledRules where rule.isUniversal || rule.languages.contains(language)
```

### Regole da marcare `isUniversal: true`
- `double-space` (doppio spazio → spazio singolo)
- `trailing-space` (spazio finale di riga)

### Regole che restano language-specific
- Tutte le regole italiane (`it-qual-e`, `it-un-po`, ecc.) — `languages: ["it"]`, `isUniversal: false`
- Regole inglesi (`en-their-theyre`, ecc.) — `languages: ["en"]`, `isUniversal: false`

### Pipeline completa per qualsiasi lingua
```
testo selezionato
  → LanguageDetector.detect() [se "auto"]
  → RuleBasedEngine: universal rules (doppio spazio ecc.) + language-specific rules se matching
  → HarperEngine [solo se en-*]
  → LLM con language parameter → corregge grammatica/fluidità in quella lingua
```

Il LLM gestisce grammatica e fluidità per qualsiasi lingua. Le regole sono solo un pre-processing leggero.

---

## Invarianti
- `PromptEngine.swift` non cambia — riceve sempre una stringa lingua risolta, non sa nulla di "auto"
- I test esistenti non cambiano — testano con lingue fisse
- Il picker manuale in Preferenze rimane completo (90+ lingue)
- L'accessibilità AX e il rilevamento dell'app frontale non sono coinvolti
