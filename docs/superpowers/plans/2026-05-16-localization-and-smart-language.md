# Localization & Smart Language Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement three independent features: (1) universal rule engine, (2) automatic correction language detection, (3) UI localization in 7 languages.

**Architecture:** Part 3 adds `isUniversal: Bool` to `GrammarRule` so double-space/trailing-space rules fire for any language. Part 2 adds a `"auto"` sentinel to `PreferencesStore.language` and resolves it in `TextCheckCoordinator` via the existing `LanguageDetector`. Part 1 creates `Resources/*.lproj/Localizable.strings` files and copies them into the `.app` bundle via `build-app.sh`; all Italian string literals in UI files are replaced with `String(localized:)` keyed lookups.

**Tech Stack:** Swift 5.10, SwiftUI, XCTest, NaturalLanguage

---

## File map

| File | Azione |
|---|---|
| `Core/RuleBasedEngine.swift` | Modifica — `isUniversal: Bool` su `GrammarRule`; filtro OR; mark double-space + space-before-punctuation |
| `Infra/PreferencesStore.swift` | Modifica — `localeDefault()` ritorna `"auto"` |
| `Core/TextCheckCoordinator.swift` | Modifica — risolve `"auto"` via `LanguageDetector` prima di passare la lingua alle regole e all'LLM |
| `UI/GeneralTab.swift` | Modifica — `Text("Automatico...").tag("auto")` come prima voce del Picker + sezione label localized |
| `Resources/en.lproj/Localizable.strings` | Crea — English base strings (41 chiavi) |
| `Resources/it.lproj/Localizable.strings` | Crea — Italian translations |
| `Resources/zh-Hans.lproj/Localizable.strings` | Crea — Chinese Simplified |
| `Resources/hr.lproj/Localizable.strings` | Crea — Croatian |
| `Resources/da.lproj/Localizable.strings` | Crea — Danish |
| `Resources/nb.lproj/Localizable.strings` | Crea — Norwegian Bokmål |
| `Resources/el.lproj/Localizable.strings` | Crea — Greek |
| `build-app.sh` | Modifica — copia `Resources/*.lproj` in `Contents/Resources/` |
| `Package.swift` | Modifica — aggiunge .lproj all'exclude list |
| `UI/OnboardingView.swift` | Modifica — ~13 stringhe localizzate |
| `UI/MenuBarView.swift` | Modifica — ~7 stringhe localizzate |
| `UI/SuggestionView.swift` | Modifica — ~7 stringhe localizzate |
| `UI/FloatingEditor.swift` | Modifica — ~4 stringhe localizzate |
| `UI/GeneralTab.swift` | Modifica — ~4 stringhe localizzate (sezioni, stato server) |
| `App/AppDelegate.swift` | Modifica — ~3 stringhe alert localizzate |
| `Infra/ModelCatalog.swift` | Modifica — 3 reason strings localizzate |
| `Tests/Tests.swift` | Modifica — aggiungi `RuleBasedEngineUniversalTests` + `LanguageAutoDetectionTests` |

---

## Task 1: Universal Rule Engine — flag `isUniversal`

**Files:**
- Modify: `Core/RuleBasedEngine.swift` (struct GrammarRule righe 17-24; check() riga 46; makeRules() righe 145-165)
- Modify: `Tests/Tests.swift`

- [ ] **Step 1: Scrivi i test che falliscono**

Aggiungi alla fine di `Tests/Tests.swift` prima della chiusura del file:

```swift
final class RuleBasedEngineUniversalTests: XCTestCase {
    func testDoubleSpace_appliesForChineseLanguage() async {
        let result = await RuleBasedEngine.shared.check("Hello  world", language: "zh")
        XCTAssertEqual(result.text, "Hello world")
        XCTAssertTrue(result.hasFixes)
    }

    func testDoubleSpace_appliesForGreekLanguage() async {
        let result = await RuleBasedEngine.shared.check("Γεια  σου", language: "el")
        XCTAssertEqual(result.text, "Γεια σου")
    }

    func testDoubleSpace_appliesForCroatianLanguage() async {
        let result = await RuleBasedEngine.shared.check("Dobro  jutro", language: "hr")
        XCTAssertEqual(result.text, "Dobro jutro")
    }

    func testItalianRule_doesNotApplyForChinese() async {
        let result = await RuleBasedEngine.shared.check("qual'è", language: "zh")
        XCTAssertEqual(result.text, "qual'è") // no fix — it rule doesn't apply to zh
    }

    func testSpaceBeforePunctuation_appliesForJapanese() async {
        let result = await RuleBasedEngine.shared.check("Ciao !", language: "ja")
        XCTAssertEqual(result.text, "Ciao!")
    }
}
```

- [ ] **Step 2: Esegui per verificare che i test falliscano**

```bash
cd /Users/eugeniozamengopontrelli/Desktop/RefineClone && swift test --filter RuleBasedEngineUniversalTests 2>&1 | tail -20
```

Atteso: `testDoubleSpace_appliesForChineseLanguage` FAIL (double-space non si applica a "zh").

- [ ] **Step 3: Aggiungi `isUniversal` a `GrammarRule`**

In `Core/RuleBasedEngine.swift`, sostituisci la struct `GrammarRule` (righe 17-24):

```swift
struct GrammarRule: Sendable {
    let id: String
    let pattern: String
    let options: NSRegularExpression.Options
    let replacement: RegexReplacement
    let reason: String
    let languages: Set<String>
    let isUniversal: Bool
}
```

- [ ] **Step 4: Aggiorna il filtro in `check()`**

In `Core/RuleBasedEngine.swift`, riga 46, sostituisci:

```swift
        for (rule, regex) in compiledRules where rule.languages.contains(language) {
```

con:

```swift
        for (rule, regex) in compiledRules where rule.isUniversal || rule.languages.contains(language) {
```

- [ ] **Step 5: Aggiorna `makeRules()` — aggiungi `isUniversal` a tutte le regole**

In `Core/RuleBasedEngine.swift`, sostituisci l'intera funzione `makeRules()` (righe 69-187):

```swift
    private static func makeRules() -> [GrammarRule] {
        [
            GrammarRule(
                id: "it-qual-e",
                pattern: "(?i)qual'è",
                options: [],
                replacement: { match in match.hasPrefix("Q") ? "Qual è" : "qual è" },
                reason: "«Qual è» si scrive senza apostrofo (troncamento, non elisione)",
                languages: ["it"],
                isUniversal: false
            ),
            GrammarRule(
                id: "it-un-po",
                pattern: "un pò",
                options: [],
                replacement: { _ in "un po'" },
                reason: "«Po'» è troncamento di «poco», vuole l'apostrofo non l'accento",
                languages: ["it"],
                isUniversal: false
            ),
            GrammarRule(
                id: "it-e-accento",
                pattern: "(?<![a-zA-Z])e'(?=\\s|[,.!?;:]|$)",
                options: [],
                replacement: { _ in "è" },
                reason: "«È» verbo vuole l'accento, non l'apostrofo",
                languages: ["it"],
                isUniversal: false
            ),
            GrammarRule(
                id: "it-ne-accento",
                pattern: "(?<![a-zA-Z])ne'(?=\\s|[,.!?;:]|$)",
                options: [],
                replacement: { _ in "né" },
                reason: "«Né» congiunzione vuole l'accento, non l'apostrofo",
                languages: ["it"],
                isUniversal: false
            ),
            GrammarRule(
                id: "it-se-accento",
                pattern: "(?<![a-zA-Z])se'(?=\\s|[,.!?;:]|$)",
                options: [],
                replacement: { _ in "sé" },
                reason: "«Sé» pronome vuole l'accento, non l'apostrofo",
                languages: ["it"],
                isUniversal: false
            ),
            GrammarRule(
                id: "it-da-accento",
                pattern: "(?<![a-zA-Z])da'(?=\\s|[,.!?;:]|$)",
                options: [],
                replacement: { _ in "dà" },
                reason: "«Dà» voce del verbo dare vuole l'accento",
                languages: ["it"],
                isUniversal: false
            ),
            GrammarRule(
                id: "it-li-accento",
                pattern: "(?<![a-zA-Z])li'(?=\\s|[,.!?;:]|$)",
                options: [],
                replacement: { _ in "lì" },
                reason: "«Lì» avverbio vuole l'accento, non l'apostrofo",
                languages: ["it"],
                isUniversal: false
            ),
            GrammarRule(
                id: "it-la-accento",
                pattern: "(?<![a-zA-Z])la'(?=\\s|[,.!?;:]|$)",
                options: [],
                replacement: { _ in "là" },
                reason: "«Là» avverbio vuole l'accento, non l'apostrofo",
                languages: ["it"],
                isUniversal: false
            ),
            GrammarRule(
                id: "it-si-accento",
                pattern: "(?<![a-zA-Z])si'(?=\\s|[,.!?;:]|$)",
                options: [],
                replacement: { _ in "sì" },
                reason: "«Sì» affermativo vuole l'accento, non l'apostrofo",
                languages: ["it"],
                isUniversal: false
            ),
            GrammarRule(
                id: "double-space",
                pattern: "  +",
                options: [],
                replacement: { _ in " " },
                reason: "Spazio doppio",
                languages: [],
                isUniversal: true
            ),
            GrammarRule(
                id: "space-before-punctuation",
                pattern: "\\s+([,.!?;:])",
                options: [],
                replacement: { match in
                    if let range = match.range(of: "[,.!?;:]", options: .regularExpression) {
                        return String(match[range])
                    }
                    return match
                },
                reason: "Niente spazio prima della punteggiatura",
                languages: [],
                isUniversal: true
            ),
            GrammarRule(
                id: "en-their-theyre",
                pattern: "(?i)\\btheir\\b(?=\\s+(?:going|coming|running|walking|doing|making|trying|looking|working|playing|saying|thinking|getting|giving|taking|leaving|putting|bringing|asking|helping|talking|turning|starting|showing|moving|living|believing|holding|writing|providing|sitting|standing|losing|paying|meeting|including|continuing|setting|learning|leading|understanding|watching|following|creating|speaking|spending|growing|opening|winning|teaching|offering|remembering|considering|appearing|buying|serving|achieving|dying|developing|sending|building|staying|falling|cutting|reaching|killing|remaining|suggesting|raising|passing|selling|requiring|reporting|deciding|pulling))",
                options: [],
                replacement: { match in match.hasPrefix("T") ? "They're" : "they're" },
                reason: "«They're» = they are; «their» = possessivo",
                languages: ["en"],
                isUniversal: false
            ),
            GrammarRule(
                id: "en-your-vs-youre",
                pattern: "(?i)\\byour\\b(?=\\s+(?:welcome|right|wrong|absolutely|correct|kidding|joking|being|doing|going|coming|looking|trying|making|very))",
                options: [],
                replacement: { match in
                    match.hasPrefix("Y") && match.hasPrefix("Your") ? "You're" : "you're"
                },
                reason: "«You're» = you are; «your» = possessivo",
                languages: ["en"],
                isUniversal: false
            ),
        ]
    }
```

- [ ] **Step 6: Verifica build e test**

```bash
swift build 2>&1 | grep -E "error:|Build complete" && swift test --filter RuleBasedEngineUniversalTests 2>&1 | tail -10
```

Atteso: `Build complete!` + tutti e 5 i nuovi test PASS.

- [ ] **Step 7: Verifica che i test esistenti siano ancora verdi**

```bash
swift test --filter RuleBasedEngineTests 2>&1 | tail -10
```

Atteso: tutti PASS (il test `testDoubleSpace_fixes` usa language "it" che ora è coperto da `isUniversal: true`).

- [ ] **Step 8: Commit**

```bash
git add Core/RuleBasedEngine.swift Tests/Tests.swift
git commit -m "feat: universal rules — double-space and space-before-punctuation apply to all languages"
```

---

## Task 2: "auto" sentinel — rilevamento automatico della lingua

**Files:**
- Modify: `Infra/PreferencesStore.swift` (riga 309-311, funzione `localeDefault()`)
- Modify: `Core/TextCheckCoordinator.swift` (righe 49-55, dentro la closure `performCheck`)
- Modify: `Tests/Tests.swift`

- [ ] **Step 1: Scrivi i test che falliscono**

Aggiungi alla fine di `Tests/Tests.swift`:

```swift
final class LanguageAutoDetectionTests: XCTestCase {
    func testDetect_englishText_returnsEn() {
        let lang = LanguageDetector.detect(
            text: "The quick brown fox jumps over the lazy dog",
            fallbackLanguage: "it"
        )
        XCTAssertEqual(lang, "en")
    }

    func testDetect_italianText_returnsIt() {
        let lang = LanguageDetector.detect(
            text: "Il gatto è sul tavolo e mangia la pasta",
            fallbackLanguage: "en"
        )
        XCTAssertEqual(lang, "it")
    }

    func testDetect_chineseText_returnsZh() {
        let lang = LanguageDetector.detect(
            text: "你好世界，这是一个测试句子。",
            fallbackLanguage: "en"
        )
        // NLLanguageRecognizer returns "zh-Hans" or "zh" — both acceptable
        XCTAssertTrue(lang.hasPrefix("zh"), "Expected Chinese, got \(lang)")
    }

    func testDetect_shortText_returnsFallback() {
        let lang = LanguageDetector.detect(
            text: "Hi",
            fallbackLanguage: "de"
        )
        // Short text may return fallback or still detect — this tests that it doesn't crash
        XCTAssertFalse(lang.isEmpty)
    }

    func testLocaleDefault_returnsAuto() {
        // Verifica che nuove installazioni usino "auto"
        XCTAssertEqual(PreferencesStore.localeDefaultForTesting(), "auto")
    }
}
```

Nota: `PreferencesStore.localeDefaultForTesting()` è un metodo `internal` che aggiungeremo nel prossimo step.

- [ ] **Step 2: Esegui per verificare che falliscano**

```bash
swift test --filter LanguageAutoDetectionTests 2>&1 | tail -20
```

Atteso: errore di compilazione — `localeDefaultForTesting` non esiste.

- [ ] **Step 3: Modifica `localeDefault()` in `PreferencesStore.swift`**

In `Infra/PreferencesStore.swift`, sostituisci `localeDefault()` (righe 309-311):

```swift
    private static func localeDefault() -> String {
        return "auto"
    }

    // Internal accessor for testing only
    static func localeDefaultForTesting() -> String {
        localeDefault()
    }
```

- [ ] **Step 4: Risolvi "auto" in `TextCheckCoordinator.swift`**

In `Core/TextCheckCoordinator.swift`, dentro la closure `performCheck` (riga 50), sostituisci:

```swift
            let language = await MainActor.run { PreferencesStore.shared.language }
```

con:

```swift
            let storedLanguage = await MainActor.run { PreferencesStore.shared.language }
            let language = storedLanguage == "auto"
                ? LanguageDetector.detect(
                    text: text,
                    fallbackLanguage: Locale.current.language.languageCode?.identifier ?? "en"
                  )
                : storedLanguage
```

- [ ] **Step 5: Verifica build e test**

```bash
swift build 2>&1 | grep -E "error:|Build complete" && swift test --filter LanguageAutoDetectionTests 2>&1 | tail -15
```

Atteso: `Build complete!` + tutti e 5 i test PASS (il test `testLocaleDefault_returnsAuto` verifica la modifica a `localeDefault()`).

- [ ] **Step 6: Verifica che i test esistenti siano ancora verdi**

```bash
swift test 2>&1 | tail -10
```

Atteso: tutti i test PASS.

- [ ] **Step 7: Commit**

```bash
git add Infra/PreferencesStore.swift Core/TextCheckCoordinator.swift Tests/Tests.swift
git commit -m "feat: auto language detection — resolves 'auto' sentinel via NLLanguageRecognizer"
```

---

## Task 3: Picker "Automatico" in GeneralTab + infrastruttura .lproj

**Files:**
- Modify: `UI/GeneralTab.swift`
- Modify: `Package.swift`
- Modify: `build-app.sh`
- Create: `Resources/en.lproj/Localizable.strings`
- Create: `Resources/it.lproj/Localizable.strings`
- Create: `Resources/zh-Hans.lproj/Localizable.strings`
- Create: `Resources/hr.lproj/Localizable.strings`
- Create: `Resources/da.lproj/Localizable.strings`
- Create: `Resources/nb.lproj/Localizable.strings`
- Create: `Resources/el.lproj/Localizable.strings`

- [ ] **Step 1: Aggiungi "Automatico" come prima voce del language Picker**

In `UI/GeneralTab.swift`, dentro `Section("Lingua")`, trova `Picker("Lingua", selection: $prefs.language)`. Aggiungi prima di `Text("Europee")...`:

```swift
                Picker("Lingua", selection: $prefs.language) {
                    Text(String(localized: "prefs.language.auto")).tag("auto")
                    Divider()
                    Text("Europee").font(.caption).foregroundStyle(.secondary).disabled(true)
                    // ... resto invariato
```

Sostituisci solo la riga `Picker("Lingua", selection: $prefs.language) {` con il blocco che include la prima voce aggiunta sopra (il resto del Picker rimane identico).

La modifica esatta — in `UI/GeneralTab.swift`, riga 87, sostituisci:

```swift
                Picker("Lingua", selection: $prefs.language) {
                    Text("Europee").font(.caption).foregroundStyle(.secondary).disabled(true)
```

con:

```swift
                Picker("Lingua", selection: $prefs.language) {
                    Text(String(localized: "prefs.language.auto")).tag("auto")
                    Divider()
                    Text("Europee").font(.caption).foregroundStyle(.secondary).disabled(true)
```

- [ ] **Step 2: Aggiungi le directory .lproj all'exclude list di `Package.swift`**

In `Package.swift`, aggiungi alla lista `exclude`:

```swift
            exclude: [
                "Resources/Info.plist",
                "Resources/RefineClone.entitlements",
                "Resources/en.lproj",
                "Resources/it.lproj",
                "Resources/zh-Hans.lproj",
                "Resources/hr.lproj",
                "Resources/da.lproj",
                "Resources/nb.lproj",
                "Resources/el.lproj",
                "PopClip",
                "Package.swift",
                "README.md",
                "CHANGELOG.md",
                ".gitignore",
                "Tests",
                ".build",
                "setup-dev.sh",
                "build-app.sh"
            ]
```

- [ ] **Step 3: Aggiorna `build-app.sh` per copiare le directory .lproj**

In `build-app.sh`, dopo la riga `mkdir -p "${MACOS}"`, aggiungi:

```bash
mkdir -p "${CONTENTS}/Resources"

# Copy .lproj localization directories
for lproj in Resources/*.lproj; do
    if [ -d "$lproj" ]; then
        cp -r "$lproj" "${CONTENTS}/Resources/"
    fi
done
```

La sezione del file, dopo la modifica, da `rm -rf "${APP_DIR}"` fino a `cp "${BINARY_PATH}"`:

```bash
rm -rf "${APP_DIR}"
mkdir -p "${MACOS}"

mkdir -p "${CONTENTS}/Resources"

# Copy .lproj localization directories
for lproj in Resources/*.lproj; do
    if [ -d "$lproj" ]; then
        cp -r "$lproj" "${CONTENTS}/Resources/"
    fi
done

cp "${BINARY_PATH}" "${MACOS}/RefineClone"
```

- [ ] **Step 4: Crea `Resources/en.lproj/Localizable.strings`**

```bash
mkdir -p /Users/eugeniozamengopontrelli/Desktop/RefineClone/Resources/en.lproj
```

Crea il file `Resources/en.lproj/Localizable.strings` con contenuto:

```
/* Onboarding */
"onboarding.step.0" = "Welcome";
"onboarding.step.1" = "Accessibility";
"onboarding.step.2" = "AI Model";
"onboarding.step.3" = "Ready";
"onboarding.welcome.title" = "Welcome to RefineClone";
"onboarding.welcome.feature.correction.title" = "Quick Correction";
"onboarding.welcome.feature.correction.detail" = "Select text in any app and use the shortcut to correct grammar and style.";
"onboarding.welcome.feature.models.title" = "Local & Cloud Models";
"onboarding.welcome.feature.models.detail" = "Use Ollama or llama.cpp locally, or connect OpenAI / OpenRouter for a cloud experience.";
"onboarding.welcome.feature.shortcuts.title" = "Customizable Shortcuts";
"onboarding.welcome.feature.shortcuts.detail" = "Open Preferences (menu bar icon) to configure grammar, fluency and explanations.";
"onboarding.accessibility.title" = "Accessibility Access";
"onboarding.accessibility.body" = "RefineClone needs accessibility access to read and correct text in other apps.";
"onboarding.accessibility.granted" = "Access granted";
"onboarding.accessibility.instructions" = "Open System Settings → Privacy & Security → Accessibility and enable RefineClone.";
"onboarding.accessibility.open_settings" = "Open Settings";
"onboarding.model.title" = "AI Model Download";
"onboarding.model.select_placeholder" = "Select model";
"onboarding.model.ready" = "Model ready";
"onboarding.model.retry" = "Retry";
"onboarding.model.download_prompt" = "We'll download the recommended model for offline correction. Requires ~2-4 GB.";
"onboarding.ready.title" = "All set!";
"onboarding.nav.back" = "Back";
"onboarding.nav.next" = "Next";
"onboarding.nav.start" = "Start";
"onboarding.nav.download" = "Download and continue";
"onboarding.nav.downloading" = "Downloading...";

/* Menu Bar */
"menu.accessibility.ok" = "Accessibility: OK";
"menu.accessibility.reenable" = "Accessibility: Re-enable in Settings →";
"menu.realtime" = "Real-Time Check";
"menu.grammar" = "Check Grammar (Cmd+Shift+E)";
"menu.fluency" = "Check Fluency (Cmd+Shift+T)";
"menu.editor" = "Open Editor (Cmd+Shift+F)";
"menu.replace" = "Replace (Cmd+Shift+R)";
"menu.translate" = "Translate (Cmd+Shift+Y)";
"menu.coach" = "Writing Coach (Cmd+Shift+C)";
"menu.preferences" = "Preferences...";
"menu.quit" = "Quit";

/* Suggestion & Floating Editor */
"suggestion.tone.formal" = "Formal";
"suggestion.tone.informal" = "Informal";
"suggestion.tone.neutral" = "Neutral";
"suggestion.tone.academic" = "Academic";
"suggestion.tone.technical" = "Technical";
"suggestion.tone.detected_prefix" = "Detected tone:";
"suggestion.header.analyzing" = "Analyzing...";
"suggestion.header.correcting" = "Correcting...";
"suggestion.header.suggestion" = "Suggestion";
"suggestion.header.fluency" = "Fluency";
"suggestion.header.no_errors" = "No errors";
"suggestion.header.error" = "Error";
"suggestion.header.too_long" = "Text too long";
"editor.panel.original" = "Original";
"editor.panel.corrected" = "Corrected";
"editor.placeholder" = "The corrected text will appear here";
"editor.button.check" = "Check";
"editor.button.checking" = "Checking…";
"editor.button.copy" = "Copy";
"editor.mode.grammar" = "Grammar";
"editor.mode.fluency" = "Fluency";

/* Preferences */
"prefs.language.auto" = "Automatic (detect from text)";
"prefs.section.corrector" = "Corrector (Cmd+Shift+E)";
"prefs.section.fluency_service" = "Fluency (Cmd+Shift+T)";
"prefs.server.running" = "llama-server: running";
"prefs.server.stopped" = "llama-server: stopped";

/* Alerts (AppDelegate) */
"alert.ollama.title" = "Ollama not detected";
"alert.ollama.body" = "The service is configured to use Ollama (localhost:11434), but the server does not appear to be running. Start Ollama or change the service in Preferences.";
"alert.shortcuts.title" = "Shortcuts unavailable";
"alert.shortcuts.body_format" = "The following shortcuts are already in use:\n%@\n\nChange them in Preferences.";
"alert.ok" = "OK";
"alert.window.welcome" = "Welcome";

/* Model reasons (ModelCatalog) */
"model.qwen.reason" = "Minimum RAM usage — ideal for short texts and Chinese";
"model.gemma2b.reason" = "Good quality for Western languages — Mac with less than 16 GB RAM";
"model.gemma4b.reason" = "Maximum quality for Western languages — requires Mac with 16 GB RAM or more";
```

- [ ] **Step 5: Crea `Resources/it.lproj/Localizable.strings`**

```bash
mkdir -p /Users/eugeniozamengopontrelli/Desktop/RefineClone/Resources/it.lproj
```

Crea il file `Resources/it.lproj/Localizable.strings`:

```
/* Onboarding */
"onboarding.step.0" = "Benvenuto";
"onboarding.step.1" = "Accessibilità";
"onboarding.step.2" = "Modello AI";
"onboarding.step.3" = "Pronto";
"onboarding.welcome.title" = "Benvenuto in RefineClone";
"onboarding.welcome.feature.correction.title" = "Correzione rapida";
"onboarding.welcome.feature.correction.detail" = "Seleziona del testo in qualsiasi app e usa la scorciatoia per correggere grammatica e stile.";
"onboarding.welcome.feature.models.title" = "Modelli locali e cloud";
"onboarding.welcome.feature.models.detail" = "Usa Ollama o llama.cpp in locale, oppure connetti OpenAI / OpenRouter per un'esperienza cloud.";
"onboarding.welcome.feature.shortcuts.title" = "Scorciatoie personalizzabili";
"onboarding.welcome.feature.shortcuts.detail" = "Apri le Preferenze (icona menu bar) per configurare grammatica, fluenza e spiegazioni.";
"onboarding.accessibility.title" = "Accesso per l'Accessibilità";
"onboarding.accessibility.body" = "RefineClone ha bisogno dell'accesso per l'accessibilità per leggere e correggere il testo in altre app.";
"onboarding.accessibility.granted" = "Accesso concesso";
"onboarding.accessibility.instructions" = "Apri Impostazioni di Sistema → Privacy e Sicurezza → Accessibilità e abilita RefineClone.";
"onboarding.accessibility.open_settings" = "Apri Impostazioni";
"onboarding.model.title" = "Download Modello AI";
"onboarding.model.select_placeholder" = "Seleziona modello";
"onboarding.model.ready" = "Modello pronto";
"onboarding.model.retry" = "Riprova";
"onboarding.model.download_prompt" = "Scarichiamo il modello consigliato per la correzione offline. Richiede ~2-4 GB.";
"onboarding.ready.title" = "Tutto pronto!";
"onboarding.nav.back" = "Indietro";
"onboarding.nav.next" = "Avanti";
"onboarding.nav.start" = "Inizia";
"onboarding.nav.download" = "Scarica e continua";
"onboarding.nav.downloading" = "Download in corso...";

/* Menu Bar */
"menu.accessibility.ok" = "Accessibilità: OK";
"menu.accessibility.reenable" = "Accessibilità: Riabilita in Impostazioni →";
"menu.realtime" = "Controllo in Tempo Reale";
"menu.grammar" = "Controlla Grammatica (Cmd+Shift+E)";
"menu.fluency" = "Controlla Fluidità (Cmd+Shift+T)";
"menu.editor" = "Apri Editor (Cmd+Shift+F)";
"menu.replace" = "Sostituisci (Cmd+Shift+R)";
"menu.translate" = "Traduci (Cmd+Shift+Y)";
"menu.coach" = "Writing Coach (Cmd+Shift+C)";
"menu.preferences" = "Preferenze...";
"menu.quit" = "Esci";

/* Suggestion & Floating Editor */
"suggestion.tone.formal" = "Formale";
"suggestion.tone.informal" = "Informale";
"suggestion.tone.neutral" = "Neutrale";
"suggestion.tone.academic" = "Accademico";
"suggestion.tone.technical" = "Tecnico";
"suggestion.tone.detected_prefix" = "Tono rilevato:";
"suggestion.header.analyzing" = "Analizzando...";
"suggestion.header.correcting" = "Correggendo...";
"suggestion.header.suggestion" = "Suggerimento";
"suggestion.header.fluency" = "Fluidità";
"suggestion.header.no_errors" = "Nessun errore";
"suggestion.header.error" = "Errore";
"suggestion.header.too_long" = "Testo troppo lungo";
"editor.panel.original" = "Originale";
"editor.panel.corrected" = "Corretto";
"editor.placeholder" = "Il testo corretto apparirà qui";
"editor.button.check" = "Controlla";
"editor.button.checking" = "Controllando…";
"editor.button.copy" = "Copia";
"editor.mode.grammar" = "Grammatica";
"editor.mode.fluency" = "Fluidità";

/* Preferences */
"prefs.language.auto" = "Automatico (rileva dal testo)";
"prefs.section.corrector" = "Correttore (Cmd+Shift+E)";
"prefs.section.fluency_service" = "Fluency (Cmd+Shift+T)";
"prefs.server.running" = "llama-server: attivo";
"prefs.server.stopped" = "llama-server: fermo";

/* Alerts (AppDelegate) */
"alert.ollama.title" = "Ollama non rilevato";
"alert.ollama.body" = "Il service è configurato per usare Ollama (localhost:11434), ma il server non risulta in esecuzione. Avvia Ollama o modifica il service nelle Preferenze.";
"alert.shortcuts.title" = "Scorciatoie non disponibili";
"alert.shortcuts.body_format" = "Le seguenti scorciatoie sono già in uso:\n%@\n\nModificale nelle Preferenze.";
"alert.ok" = "OK";
"alert.window.welcome" = "Benvenuto";

/* Model reasons (ModelCatalog) */
"model.qwen.reason" = "Minimo consumo RAM — ideale per testi brevi e lingua cinese";
"model.gemma2b.reason" = "Buona qualità per lingue occidentali — Mac con meno di 16 GB";
"model.gemma4b.reason" = "Massima qualità per lingue occidentali — richiede Mac con 16 GB RAM o più";
```

- [ ] **Step 6: Crea i file per le 5 lingue rimanenti**

Crea `Resources/zh-Hans.lproj/Localizable.strings`:

```bash
mkdir -p /Users/eugeniozamengopontrelli/Desktop/RefineClone/Resources/zh-Hans.lproj
```

Contenuto `Resources/zh-Hans.lproj/Localizable.strings`:

```
"onboarding.step.0" = "欢迎";
"onboarding.step.1" = "辅助功能";
"onboarding.step.2" = "AI 模型";
"onboarding.step.3" = "准备就绪";
"onboarding.welcome.title" = "欢迎使用 RefineClone";
"onboarding.welcome.feature.correction.title" = "快速纠正";
"onboarding.welcome.feature.correction.detail" = "在任意应用中选择文字，使用快捷键纠正语法和文风。";
"onboarding.welcome.feature.models.title" = "本地和云端模型";
"onboarding.welcome.feature.models.detail" = "使用本地 Ollama 或 llama.cpp，或连接 OpenAI / OpenRouter 使用云端体验。";
"onboarding.welcome.feature.shortcuts.title" = "可自定义快捷键";
"onboarding.welcome.feature.shortcuts.detail" = "打开偏好设置（菜单栏图标）来配置语法、流畅度和说明。";
"onboarding.accessibility.title" = "辅助功能访问";
"onboarding.accessibility.body" = "RefineClone 需要辅助功能访问权限，以读取和纠正其他应用中的文字。";
"onboarding.accessibility.granted" = "已获得访问权限";
"onboarding.accessibility.instructions" = "打开系统设置 → 隐私与安全性 → 辅助功能，并启用 RefineClone。";
"onboarding.accessibility.open_settings" = "打开设置";
"onboarding.model.title" = "AI 模型下载";
"onboarding.model.select_placeholder" = "选择模型";
"onboarding.model.ready" = "模型已就绪";
"onboarding.model.retry" = "重试";
"onboarding.model.download_prompt" = "我们将下载推荐的离线纠正模型，需要约 2-4 GB。";
"onboarding.ready.title" = "准备就绪！";
"onboarding.nav.back" = "返回";
"onboarding.nav.next" = "下一步";
"onboarding.nav.start" = "开始";
"onboarding.nav.download" = "下载并继续";
"onboarding.nav.downloading" = "下载中...";
"menu.accessibility.ok" = "辅助功能：正常";
"menu.accessibility.reenable" = "辅助功能：在设置中重新启用 →";
"menu.realtime" = "实时检查";
"menu.grammar" = "检查语法 (Cmd+Shift+E)";
"menu.fluency" = "检查流畅度 (Cmd+Shift+T)";
"menu.editor" = "打开编辑器 (Cmd+Shift+F)";
"menu.replace" = "替换 (Cmd+Shift+R)";
"menu.translate" = "翻译 (Cmd+Shift+Y)";
"menu.coach" = "写作辅导 (Cmd+Shift+C)";
"menu.preferences" = "偏好设置...";
"menu.quit" = "退出";
"suggestion.tone.formal" = "正式";
"suggestion.tone.informal" = "非正式";
"suggestion.tone.neutral" = "中性";
"suggestion.tone.academic" = "学术";
"suggestion.tone.technical" = "技术";
"suggestion.tone.detected_prefix" = "检测到的语气：";
"suggestion.header.analyzing" = "分析中...";
"suggestion.header.correcting" = "纠正中...";
"suggestion.header.suggestion" = "建议";
"suggestion.header.fluency" = "流畅度";
"suggestion.header.no_errors" = "没有错误";
"suggestion.header.error" = "错误";
"suggestion.header.too_long" = "文字过长";
"editor.panel.original" = "原文";
"editor.panel.corrected" = "已纠正";
"editor.placeholder" = "纠正后的文字将显示在这里";
"editor.button.check" = "检查";
"editor.button.checking" = "检查中…";
"editor.button.copy" = "复制";
"editor.mode.grammar" = "语法";
"editor.mode.fluency" = "流畅度";
"prefs.language.auto" = "自动（从文字检测）";
"prefs.section.corrector" = "纠正器 (Cmd+Shift+E)";
"prefs.section.fluency_service" = "流畅度 (Cmd+Shift+T)";
"prefs.server.running" = "llama-server：运行中";
"prefs.server.stopped" = "llama-server：已停止";
"alert.ollama.title" = "未检测到 Ollama";
"alert.ollama.body" = "服务已配置为使用 Ollama (localhost:11434)，但服务器似乎未在运行。请启动 Ollama 或在偏好设置中更改服务。";
"alert.shortcuts.title" = "快捷键不可用";
"alert.shortcuts.body_format" = "以下快捷键已被占用：\n%@\n\n请在偏好设置中更改它们。";
"alert.ok" = "好";
"alert.window.welcome" = "欢迎";
"model.qwen.reason" = "最低内存占用 — 适合短文本和中文";
"model.gemma2b.reason" = "适合西方语言的优质模型 — 适合 16 GB 以下的 Mac";
"model.gemma4b.reason" = "适合西方语言的最高质量模型 — 需要 16 GB 或更多 RAM 的 Mac";
```

Crea `Resources/hr.lproj/Localizable.strings`:

```bash
mkdir -p /Users/eugeniozamengopontrelli/Desktop/RefineClone/Resources/hr.lproj
```

Contenuto `Resources/hr.lproj/Localizable.strings`:

```
"onboarding.step.0" = "Dobrodošli";
"onboarding.step.1" = "Pristupačnost";
"onboarding.step.2" = "AI Model";
"onboarding.step.3" = "Spremno";
"onboarding.welcome.title" = "Dobrodošli u RefineClone";
"onboarding.welcome.feature.correction.title" = "Brza korekcija";
"onboarding.welcome.feature.correction.detail" = "Odaberite tekst u bilo kojoj aplikaciji i koristite prečac za ispravljanje gramatike i stila.";
"onboarding.welcome.feature.models.title" = "Lokalni i oblačni modeli";
"onboarding.welcome.feature.models.detail" = "Koristite Ollama ili llama.cpp lokalno, ili povežite OpenAI / OpenRouter za oblačno iskustvo.";
"onboarding.welcome.feature.shortcuts.title" = "Prilagodljivi prečaci";
"onboarding.welcome.feature.shortcuts.detail" = "Otvorite Postavke (ikona trake izbornika) za konfiguraciju gramatike, tečnosti i objašnjenja.";
"onboarding.accessibility.title" = "Pristup pristupačnosti";
"onboarding.accessibility.body" = "RefineClone treba pristup pristupačnosti za čitanje i ispravljanje teksta u drugim aplikacijama.";
"onboarding.accessibility.granted" = "Pristup odobren";
"onboarding.accessibility.instructions" = "Otvorite Postavke sustava → Privatnost i sigurnost → Pristupačnost i omogućite RefineClone.";
"onboarding.accessibility.open_settings" = "Otvori postavke";
"onboarding.model.title" = "Preuzimanje AI modela";
"onboarding.model.select_placeholder" = "Odaberi model";
"onboarding.model.ready" = "Model spreman";
"onboarding.model.retry" = "Pokušaj ponovo";
"onboarding.model.download_prompt" = "Preuzet ćemo preporučeni model za offline korekciju. Potrebno je ~2-4 GB.";
"onboarding.ready.title" = "Sve je spremno!";
"onboarding.nav.back" = "Natrag";
"onboarding.nav.next" = "Naprijed";
"onboarding.nav.start" = "Pokreni";
"onboarding.nav.download" = "Preuzmi i nastavi";
"onboarding.nav.downloading" = "Preuzimanje...";
"menu.accessibility.ok" = "Pristupačnost: OK";
"menu.accessibility.reenable" = "Pristupačnost: Ponovno omogući u Postavkama →";
"menu.realtime" = "Provjera u stvarnom vremenu";
"menu.grammar" = "Provjeri gramatiku (Cmd+Shift+E)";
"menu.fluency" = "Provjeri tečnost (Cmd+Shift+T)";
"menu.editor" = "Otvori uređivač (Cmd+Shift+F)";
"menu.replace" = "Zamijeni (Cmd+Shift+R)";
"menu.translate" = "Prevedi (Cmd+Shift+Y)";
"menu.coach" = "Pisački trener (Cmd+Shift+C)";
"menu.preferences" = "Postavke...";
"menu.quit" = "Izlaz";
"suggestion.tone.formal" = "Formalno";
"suggestion.tone.informal" = "Neformalno";
"suggestion.tone.neutral" = "Neutralno";
"suggestion.tone.academic" = "Akademski";
"suggestion.tone.technical" = "Tehničko";
"suggestion.tone.detected_prefix" = "Otkriveni ton:";
"suggestion.header.analyzing" = "Analiziranje...";
"suggestion.header.correcting" = "Ispravljanje...";
"suggestion.header.suggestion" = "Prijedlog";
"suggestion.header.fluency" = "Tečnost";
"suggestion.header.no_errors" = "Nema grešaka";
"suggestion.header.error" = "Greška";
"suggestion.header.too_long" = "Tekst predugačak";
"editor.panel.original" = "Izvornik";
"editor.panel.corrected" = "Ispravljeno";
"editor.placeholder" = "Ispravljeni tekst pojavit će se ovdje";
"editor.button.check" = "Provjeri";
"editor.button.checking" = "Provjera…";
"editor.button.copy" = "Kopiraj";
"editor.mode.grammar" = "Gramatika";
"editor.mode.fluency" = "Tečnost";
"prefs.language.auto" = "Automatski (otkrij iz teksta)";
"prefs.section.corrector" = "Korektor (Cmd+Shift+E)";
"prefs.section.fluency_service" = "Tečnost (Cmd+Shift+T)";
"prefs.server.running" = "llama-server: aktivan";
"prefs.server.stopped" = "llama-server: zaustavljeno";
"alert.ollama.title" = "Ollama nije otkrivena";
"alert.ollama.body" = "Usluga je konfigurirana za korištenje Ollame (localhost:11434), ali server ne radi. Pokrenite Ollamu ili promijenite uslugu u Postavkama.";
"alert.shortcuts.title" = "Prečaci nedostupni";
"alert.shortcuts.body_format" = "Sljedeći prečaci su već u upotrebi:\n%@\n\nPromijenite ih u Postavkama.";
"alert.ok" = "U redu";
"alert.window.welcome" = "Dobrodošli";
"model.qwen.reason" = "Minimalna potrošnja RAM-a — idealno za kratke tekstove i kineski";
"model.gemma2b.reason" = "Dobra kvaliteta za zapadne jezike — Mac s manje od 16 GB RAM-a";
"model.gemma4b.reason" = "Maksimalna kvaliteta za zapadne jezike — zahtijeva Mac s 16 GB RAM-a ili više";
```

Crea `Resources/da.lproj/Localizable.strings`:

```bash
mkdir -p /Users/eugeniozamengopontrelli/Desktop/RefineClone/Resources/da.lproj
```

Contenuto `Resources/da.lproj/Localizable.strings`:

```
"onboarding.step.0" = "Velkommen";
"onboarding.step.1" = "Tilgængelighed";
"onboarding.step.2" = "AI-model";
"onboarding.step.3" = "Klar";
"onboarding.welcome.title" = "Velkommen til RefineClone";
"onboarding.welcome.feature.correction.title" = "Hurtig korrektion";
"onboarding.welcome.feature.correction.detail" = "Vælg tekst i en hvilken som helst app og brug genvejen til at rette grammatik og stil.";
"onboarding.welcome.feature.models.title" = "Lokale og cloud-modeller";
"onboarding.welcome.feature.models.detail" = "Brug Ollama eller llama.cpp lokalt, eller forbind OpenAI / OpenRouter for en cloud-oplevelse.";
"onboarding.welcome.feature.shortcuts.title" = "Tilpassede genveje";
"onboarding.welcome.feature.shortcuts.detail" = "Åbn Indstillinger (menulinjeikon) for at konfigurere grammatik, flydighed og forklaringer.";
"onboarding.accessibility.title" = "Tilgængelighed";
"onboarding.accessibility.body" = "RefineClone har brug for tilgængelighed for at læse og rette tekst i andre apps.";
"onboarding.accessibility.granted" = "Adgang givet";
"onboarding.accessibility.instructions" = "Åbn Systemindstillinger → Privatliv og sikkerhed → Tilgængelighed og aktiver RefineClone.";
"onboarding.accessibility.open_settings" = "Åbn indstillinger";
"onboarding.model.title" = "Download AI-model";
"onboarding.model.select_placeholder" = "Vælg model";
"onboarding.model.ready" = "Model klar";
"onboarding.model.retry" = "Prøv igen";
"onboarding.model.download_prompt" = "Vi downloader den anbefalede model til offline korrektion. Kræver ~2-4 GB.";
"onboarding.ready.title" = "Klar!";
"onboarding.nav.back" = "Tilbage";
"onboarding.nav.next" = "Næste";
"onboarding.nav.start" = "Start";
"onboarding.nav.download" = "Download og fortsæt";
"onboarding.nav.downloading" = "Downloader...";
"menu.accessibility.ok" = "Tilgængelighed: OK";
"menu.accessibility.reenable" = "Tilgængelighed: Genaktiver i Indstillinger →";
"menu.realtime" = "Realtidstjek";
"menu.grammar" = "Tjek grammatik (Cmd+Shift+E)";
"menu.fluency" = "Tjek flydighed (Cmd+Shift+T)";
"menu.editor" = "Åbn editor (Cmd+Shift+F)";
"menu.replace" = "Erstat (Cmd+Shift+R)";
"menu.translate" = "Oversæt (Cmd+Shift+Y)";
"menu.coach" = "Skrivecoach (Cmd+Shift+C)";
"menu.preferences" = "Indstillinger...";
"menu.quit" = "Afslut";
"suggestion.tone.formal" = "Formel";
"suggestion.tone.informal" = "Uformel";
"suggestion.tone.neutral" = "Neutral";
"suggestion.tone.academic" = "Akademisk";
"suggestion.tone.technical" = "Teknisk";
"suggestion.tone.detected_prefix" = "Registreret tone:";
"suggestion.header.analyzing" = "Analyserer...";
"suggestion.header.correcting" = "Retter...";
"suggestion.header.suggestion" = "Forslag";
"suggestion.header.fluency" = "Flydighed";
"suggestion.header.no_errors" = "Ingen fejl";
"suggestion.header.error" = "Fejl";
"suggestion.header.too_long" = "Tekst for lang";
"editor.panel.original" = "Original";
"editor.panel.corrected" = "Rettet";
"editor.placeholder" = "Den rettede tekst vises her";
"editor.button.check" = "Tjek";
"editor.button.checking" = "Tjekker…";
"editor.button.copy" = "Kopiér";
"editor.mode.grammar" = "Grammatik";
"editor.mode.fluency" = "Flydighed";
"prefs.language.auto" = "Automatisk (registrer fra tekst)";
"prefs.section.corrector" = "Korrektor (Cmd+Shift+E)";
"prefs.section.fluency_service" = "Flydighed (Cmd+Shift+T)";
"prefs.server.running" = "llama-server: aktiv";
"prefs.server.stopped" = "llama-server: stoppet";
"alert.ollama.title" = "Ollama ikke fundet";
"alert.ollama.body" = "Tjenesten er konfigureret til at bruge Ollama (localhost:11434), men serveren ser ikke ud til at køre. Start Ollama eller skift tjeneste i Indstillinger.";
"alert.shortcuts.title" = "Genveje ikke tilgængelige";
"alert.shortcuts.body_format" = "Følgende genveje er allerede i brug:\n%@\n\nÆndre dem i Indstillinger.";
"alert.ok" = "OK";
"alert.window.welcome" = "Velkommen";
"model.qwen.reason" = "Minimalt RAM-forbrug — ideelt til korte tekster og kinesisk";
"model.gemma2b.reason" = "God kvalitet til vestlige sprog — Mac med under 16 GB RAM";
"model.gemma4b.reason" = "Maksimal kvalitet til vestlige sprog — kræver Mac med 16 GB RAM eller mere";
```

Crea `Resources/nb.lproj/Localizable.strings`:

```bash
mkdir -p /Users/eugeniozamengopontrelli/Desktop/RefineClone/Resources/nb.lproj
```

Contenuto `Resources/nb.lproj/Localizable.strings`:

```
"onboarding.step.0" = "Velkommen";
"onboarding.step.1" = "Tilgjengelighet";
"onboarding.step.2" = "AI-modell";
"onboarding.step.3" = "Klar";
"onboarding.welcome.title" = "Velkommen til RefineClone";
"onboarding.welcome.feature.correction.title" = "Rask korrektur";
"onboarding.welcome.feature.correction.detail" = "Velg tekst i en hvilken som helst app og bruk snarveien til å rette grammatikk og stil.";
"onboarding.welcome.feature.models.title" = "Lokale og skymodeller";
"onboarding.welcome.feature.models.detail" = "Bruk Ollama eller llama.cpp lokalt, eller koble til OpenAI / OpenRouter for en skyopplevelse.";
"onboarding.welcome.feature.shortcuts.title" = "Tilpassbare snarveier";
"onboarding.welcome.feature.shortcuts.detail" = "Åpne Innstillinger (menylinjeikon) for å konfigurere grammatikk, flyt og forklaringer.";
"onboarding.accessibility.title" = "Tilgjengelighet";
"onboarding.accessibility.body" = "RefineClone trenger tilgjengelighetsadgang for å lese og rette tekst i andre apper.";
"onboarding.accessibility.granted" = "Adgang gitt";
"onboarding.accessibility.instructions" = "Åpne Systeminnstillinger → Personvern og sikkerhet → Tilgjengelighet og aktiver RefineClone.";
"onboarding.accessibility.open_settings" = "Åpne innstillinger";
"onboarding.model.title" = "Last ned AI-modell";
"onboarding.model.select_placeholder" = "Velg modell";
"onboarding.model.ready" = "Modell klar";
"onboarding.model.retry" = "Prøv igjen";
"onboarding.model.download_prompt" = "Vi laster ned den anbefalte modellen for offline korrektur. Krever ~2-4 GB.";
"onboarding.ready.title" = "Alt klart!";
"onboarding.nav.back" = "Tilbake";
"onboarding.nav.next" = "Neste";
"onboarding.nav.start" = "Start";
"onboarding.nav.download" = "Last ned og fortsett";
"onboarding.nav.downloading" = "Laster ned...";
"menu.accessibility.ok" = "Tilgjengelighet: OK";
"menu.accessibility.reenable" = "Tilgjengelighet: Reaktiver i Innstillinger →";
"menu.realtime" = "Sanntidskontroll";
"menu.grammar" = "Sjekk grammatikk (Cmd+Shift+E)";
"menu.fluency" = "Sjekk flyt (Cmd+Shift+T)";
"menu.editor" = "Åpne redigerer (Cmd+Shift+F)";
"menu.replace" = "Erstatt (Cmd+Shift+R)";
"menu.translate" = "Oversett (Cmd+Shift+Y)";
"menu.coach" = "Skrivecoach (Cmd+Shift+C)";
"menu.preferences" = "Innstillinger...";
"menu.quit" = "Avslutt";
"suggestion.tone.formal" = "Formell";
"suggestion.tone.informal" = "Uformell";
"suggestion.tone.neutral" = "Nøytral";
"suggestion.tone.academic" = "Akademisk";
"suggestion.tone.technical" = "Teknisk";
"suggestion.tone.detected_prefix" = "Oppdaget tone:";
"suggestion.header.analyzing" = "Analyserer...";
"suggestion.header.correcting" = "Retter...";
"suggestion.header.suggestion" = "Forslag";
"suggestion.header.fluency" = "Flyt";
"suggestion.header.no_errors" = "Ingen feil";
"suggestion.header.error" = "Feil";
"suggestion.header.too_long" = "Tekst for lang";
"editor.panel.original" = "Original";
"editor.panel.corrected" = "Rettet";
"editor.placeholder" = "Den rettede teksten vises her";
"editor.button.check" = "Sjekk";
"editor.button.checking" = "Sjekker…";
"editor.button.copy" = "Kopier";
"editor.mode.grammar" = "Grammatikk";
"editor.mode.fluency" = "Flyt";
"prefs.language.auto" = "Automatisk (oppdag fra tekst)";
"prefs.section.corrector" = "Korrektor (Cmd+Shift+E)";
"prefs.section.fluency_service" = "Flyt (Cmd+Shift+T)";
"prefs.server.running" = "llama-server: aktiv";
"prefs.server.stopped" = "llama-server: stoppet";
"alert.ollama.title" = "Ollama ikke funnet";
"alert.ollama.body" = "Tjenesten er konfigurert til å bruke Ollama (localhost:11434), men serveren ser ikke ut til å kjøre. Start Ollama eller endre tjenesten i Innstillinger.";
"alert.shortcuts.title" = "Snarveier utilgjengelige";
"alert.shortcuts.body_format" = "Følgende snarveier er allerede i bruk:\n%@\n\nEndr dem i Innstillinger.";
"alert.ok" = "OK";
"alert.window.welcome" = "Velkommen";
"model.qwen.reason" = "Minimalt RAM-forbruk — ideelt for korte tekster og kinesisk";
"model.gemma2b.reason" = "God kvalitet for vestlige språk — Mac med under 16 GB RAM";
"model.gemma4b.reason" = "Maksimal kvalitet for vestlige språk — krever Mac med 16 GB RAM eller mer";
```

Crea `Resources/el.lproj/Localizable.strings`:

```bash
mkdir -p /Users/eugeniozamengopontrelli/Desktop/RefineClone/Resources/el.lproj
```

Contenuto `Resources/el.lproj/Localizable.strings`:

```
"onboarding.step.0" = "Καλωσόρισμα";
"onboarding.step.1" = "Προσβασιμότητα";
"onboarding.step.2" = "AI Μοντέλο";
"onboarding.step.3" = "Έτοιμο";
"onboarding.welcome.title" = "Καλωσήρθατε στο RefineClone";
"onboarding.welcome.feature.correction.title" = "Γρήγορη διόρθωση";
"onboarding.welcome.feature.correction.detail" = "Επιλέξτε κείμενο σε οποιαδήποτε εφαρμογή και χρησιμοποιήστε τη συντόμευση για διόρθωση γραμματικής και ύφους.";
"onboarding.welcome.feature.models.title" = "Τοπικά και cloud μοντέλα";
"onboarding.welcome.feature.models.detail" = "Χρησιμοποιήστε Ollama ή llama.cpp τοπικά, ή συνδεθείτε με OpenAI / OpenRouter για cloud εμπειρία.";
"onboarding.welcome.feature.shortcuts.title" = "Προσαρμόσιμες συντομεύσεις";
"onboarding.welcome.feature.shortcuts.detail" = "Ανοίξτε τις Προτιμήσεις (εικονίδιο γραμμής μενού) για τη ρύθμιση γραμματικής, ροής και εξηγήσεων.";
"onboarding.accessibility.title" = "Πρόσβαση προσβασιμότητας";
"onboarding.accessibility.body" = "Το RefineClone χρειάζεται πρόσβαση προσβασιμότητας για να διαβάζει και να διορθώνει κείμενο σε άλλες εφαρμογές.";
"onboarding.accessibility.granted" = "Πρόσβαση εγκρίθηκε";
"onboarding.accessibility.instructions" = "Ανοίξτε Ρυθμίσεις συστήματος → Απόρρητο και ασφάλεια → Προσβασιμότητα και ενεργοποιήστε το RefineClone.";
"onboarding.accessibility.open_settings" = "Άνοιγμα ρυθμίσεων";
"onboarding.model.title" = "Λήψη AI μοντέλου";
"onboarding.model.select_placeholder" = "Επιλέξτε μοντέλο";
"onboarding.model.ready" = "Μοντέλο έτοιμο";
"onboarding.model.retry" = "Επανάληψη";
"onboarding.model.download_prompt" = "Θα κατεβάσουμε το προτεινόμενο μοντέλο για offline διόρθωση. Απαιτεί ~2-4 GB.";
"onboarding.ready.title" = "Όλα έτοιμα!";
"onboarding.nav.back" = "Πίσω";
"onboarding.nav.next" = "Επόμενο";
"onboarding.nav.start" = "Έναρξη";
"onboarding.nav.download" = "Λήψη και συνέχεια";
"onboarding.nav.downloading" = "Λήψη...";
"menu.accessibility.ok" = "Προσβασιμότητα: OK";
"menu.accessibility.reenable" = "Προσβασιμότητα: Επανενεργοποίηση στις Ρυθμίσεις →";
"menu.realtime" = "Έλεγχος σε πραγματικό χρόνο";
"menu.grammar" = "Έλεγχος γραμματικής (Cmd+Shift+E)";
"menu.fluency" = "Έλεγχος ροής (Cmd+Shift+T)";
"menu.editor" = "Άνοιγμα επεξεργαστή (Cmd+Shift+F)";
"menu.replace" = "Αντικατάσταση (Cmd+Shift+R)";
"menu.translate" = "Μετάφραση (Cmd+Shift+Y)";
"menu.coach" = "Προπονητής γραφής (Cmd+Shift+C)";
"menu.preferences" = "Προτιμήσεις...";
"menu.quit" = "Έξοδος";
"suggestion.tone.formal" = "Επίσημο";
"suggestion.tone.informal" = "Ανεπίσημο";
"suggestion.tone.neutral" = "Ουδέτερο";
"suggestion.tone.academic" = "Ακαδημαϊκό";
"suggestion.tone.technical" = "Τεχνικό";
"suggestion.tone.detected_prefix" = "Ανιχνευμένος τόνος:";
"suggestion.header.analyzing" = "Ανάλυση...";
"suggestion.header.correcting" = "Διόρθωση...";
"suggestion.header.suggestion" = "Πρόταση";
"suggestion.header.fluency" = "Ροή";
"suggestion.header.no_errors" = "Καμία σφάλμα";
"suggestion.header.error" = "Σφάλμα";
"suggestion.header.too_long" = "Κείμενο πολύ μακρύ";
"editor.panel.original" = "Πρωτότυπο";
"editor.panel.corrected" = "Διορθωμένο";
"editor.placeholder" = "Το διορθωμένο κείμενο θα εμφανιστεί εδώ";
"editor.button.check" = "Έλεγχος";
"editor.button.checking" = "Έλεγχος…";
"editor.button.copy" = "Αντιγραφή";
"editor.mode.grammar" = "Γραμματική";
"editor.mode.fluency" = "Ροή";
"prefs.language.auto" = "Αυτόματο (ανίχνευση από κείμενο)";
"prefs.section.corrector" = "Διορθωτής (Cmd+Shift+E)";
"prefs.section.fluency_service" = "Ροή (Cmd+Shift+T)";
"prefs.server.running" = "llama-server: ενεργό";
"prefs.server.stopped" = "llama-server: σταματημένο";
"alert.ollama.title" = "Το Ollama δεν εντοπίστηκε";
"alert.ollama.body" = "Η υπηρεσία έχει διαμορφωθεί να χρησιμοποιεί το Ollama (localhost:11434), αλλά ο διακομιστής δεν φαίνεται να εκτελείται. Εκκινήστε το Ollama ή αλλάξτε την υπηρεσία στις Προτιμήσεις.";
"alert.shortcuts.title" = "Οι συντομεύσεις δεν είναι διαθέσιμες";
"alert.shortcuts.body_format" = "Οι παρακάτω συντομεύσεις είναι ήδη σε χρήση:\n%@\n\nΑλλάξτε τις στις Προτιμήσεις.";
"alert.ok" = "OK";
"alert.window.welcome" = "Καλωσόρισμα";
"model.qwen.reason" = "Ελάχιστη κατανάλωση RAM — ιδανικό για σύντομα κείμενα και κινεζικά";
"model.gemma2b.reason" = "Καλή ποιότητα για δυτικές γλώσσες — Mac με λιγότερο από 16 GB RAM";
"model.gemma4b.reason" = "Μέγιστη ποιότητα για δυτικές γλώσσες — απαιτεί Mac με 16 GB RAM ή περισσότερο";
```

- [ ] **Step 7: Verifica build (solo compilazione, non il contenuto .strings)**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Atteso: `Build complete!` (Package.swift ora ha le directory nel exclude list, quindi le ignorerà senza errori).

- [ ] **Step 8: Commit**

```bash
git add UI/GeneralTab.swift Package.swift build-app.sh \
    Resources/en.lproj Resources/it.lproj Resources/zh-Hans.lproj \
    Resources/hr.lproj Resources/da.lproj Resources/nb.lproj Resources/el.lproj
git commit -m "feat: add 7-language Localizable.strings + auto picker option + lproj build support"
```

---

## Task 4: Localizza OnboardingView, MenuBarView, AppDelegate

**Files:**
- Modify: `UI/OnboardingView.swift`
- Modify: `UI/MenuBarView.swift`
- Modify: `App/AppDelegate.swift`

- [ ] **Step 1: Modifica `UI/OnboardingView.swift`**

Sostituisci `private let steps = ["Benvenuto", "Accessibilità", "Modello AI", "Pronto"]` (riga 17) con:

```swift
    private let steps = [
        String(localized: "onboarding.step.0"),
        String(localized: "onboarding.step.1"),
        String(localized: "onboarding.step.2"),
        String(localized: "onboarding.step.3")
    ]
```

Sostituisci nel corpo di `welcomeStep`:

```swift
            Text("Benvenuto in RefineClone")
                .font(.title2.weight(.semibold))
                .padding(.bottom, 24)
```

con:

```swift
            Text(String(localized: "onboarding.welcome.title"))
                .font(.title2.weight(.semibold))
                .padding(.bottom, 24)
```

Sostituisci le tre `OnboardRow(...)`:

```swift
                OnboardRow(icon: "text.badge.checkmark",
                           title: String(localized: "onboarding.welcome.feature.correction.title"),
                           detail: String(localized: "onboarding.welcome.feature.correction.detail"))
                OnboardRow(icon: "character.book.closed",
                           title: String(localized: "onboarding.welcome.feature.models.title"),
                           detail: String(localized: "onboarding.welcome.feature.models.detail"))
                OnboardRow(icon: "keyboard",
                           title: String(localized: "onboarding.welcome.feature.shortcuts.title"),
                           detail: String(localized: "onboarding.welcome.feature.shortcuts.detail"))
```

Sostituisci nel corpo di `accessibilityStep`:

```swift
            Text("Accesso per l'Accessibilità")
                .font(.title2.weight(.semibold))
```

con:

```swift
            Text(String(localized: "onboarding.accessibility.title"))
                .font(.title2.weight(.semibold))
```

Sostituisci:

```swift
            Text("RefineClone ha bisogno dell'accesso per l'accessibilità per leggere e correggere il testo in altre app.")
```

con:

```swift
            Text(String(localized: "onboarding.accessibility.body"))
```

Sostituisci:

```swift
                    Label("Accesso concesso", systemImage: "checkmark.circle.fill")
```

con:

```swift
                    Label(String(localized: "onboarding.accessibility.granted"), systemImage: "checkmark.circle.fill")
```

Sostituisci:

```swift
                    Text("Apri Impostazioni di Sistema → Privacy e Sicurezza → Accessibilità e abilita RefineClone.")
```

con:

```swift
                    Text(String(localized: "onboarding.accessibility.instructions"))
```

Sostituisci:

```swift
                    Button("Apri Impostazioni") {
```

con:

```swift
                    Button(String(localized: "onboarding.accessibility.open_settings")) {
```

Nel corpo di `modelPickerButton`, sostituisci:

```swift
            Text(selectedModel?.name ?? "Seleziona modello")
```

con:

```swift
            Text(selectedModel?.name ?? String(localized: "onboarding.model.select_placeholder"))
```

Nel corpo di `modelDownloadStep`:

```swift
            Text("Download Modello AI")
                .font(.title2.weight(.semibold))
```

con:

```swift
            Text(String(localized: "onboarding.model.title"))
                .font(.title2.weight(.semibold))
```

Sostituisci:

```swift
                Label("Modello pronto", systemImage: "checkmark.circle.fill")
```

con:

```swift
                Label(String(localized: "onboarding.model.ready"), systemImage: "checkmark.circle.fill")
```

Sostituisci:

```swift
                Button("Riprova") {
                    downloadError = nil
                    startDownload()
                }
```

con:

```swift
                Button(String(localized: "onboarding.model.retry")) {
                    downloadError = nil
                    startDownload()
                }
```

Sostituisci:

```swift
                Text("Scarichiamo il modello consigliato per la correzione offline. Richiede ~2-4 GB.")
```

con:

```swift
                Text(String(localized: "onboarding.model.download_prompt"))
```

Nel corpo di `readyStep`:

```swift
            Text("Tutto pronto!")
                .font(.title2.weight(.semibold))
```

con:

```swift
            Text(String(localized: "onboarding.ready.title"))
                .font(.title2.weight(.semibold))
```

Nel `navigationButtons`, sostituisci:

```swift
                Button("Indietro") {
```

con:

```swift
                Button(String(localized: "onboarding.nav.back")) {
```

Sostituisci la riga del bottone avanti (riga 274 circa):

```swift
                Button(step == 2 ? (isDownloading ? "Download in corso..." : (downloadComplete ? "Avanti" : "Scarica e continua")) : "Avanti") {
```

con:

```swift
                Button(step == 2
                    ? (isDownloading
                        ? String(localized: "onboarding.nav.downloading")
                        : (downloadComplete
                            ? String(localized: "onboarding.nav.next")
                            : String(localized: "onboarding.nav.download")))
                    : String(localized: "onboarding.nav.next")) {
```

Sostituisci:

```swift
                Button("Inizia") {
```

con:

```swift
                Button(String(localized: "onboarding.nav.start")) {
```

Nella funzione `startDownload()`, sostituisci:

```swift
                    downloadError = "Download fallito: \(error.localizedDescription)"
```

con:

```swift
                    downloadError = String(localized: "onboarding.nav.downloading").isEmpty ? "Download failed: \(error.localizedDescription)" : "Download failed: \(error.localizedDescription)"
```

Wait — questa stringa di errore non ha una chiave dedicata nel dizionario. Lasciala in inglese:

```swift
                    downloadError = "Download failed: \(error.localizedDescription)"
```

(L'errore è tecnico e usa `localizedDescription`, lasciarlo in inglese è corretto.)

- [ ] **Step 2: Modifica `UI/MenuBarView.swift`**

Sostituisci le stringhe nel file (cerca e sostituisci una ad una):

```swift
// Riga con "Accessibilità: OK"
                        Text("Accessibilità: OK")
```
→
```swift
                        Text(String(localized: "menu.accessibility.ok"))
```

```swift
// Riga con "Accessibilità: Riabilita..."
                            Text("Accessibilità: Riabilita in Impostazioni →")
```
→
```swift
                            Text(String(localized: "menu.accessibility.reenable"))
```

```swift
                Toggle("Controllo in Tempo Reale", isOn: Bindable(prefs).realtimeEnabled)
```
→
```swift
                Toggle(String(localized: "menu.realtime"), isOn: Bindable(prefs).realtimeEnabled)
```

```swift
                        Text("Controlla Grammatica (Cmd+Shift+E)")
```
→
```swift
                        Text(String(localized: "menu.grammar"))
```

```swift
                        Text("Controlla Fluidità (Cmd+Shift+T)")
```
→
```swift
                        Text(String(localized: "menu.fluency"))
```

```swift
                        Text("Apri Editor (Cmd+Shift+F)")
```
→
```swift
                        Text(String(localized: "menu.editor"))
```

```swift
                        Text("Sostituisci (Cmd+Shift+R)")
```
→
```swift
                        Text(String(localized: "menu.replace"))
```

```swift
                        Text("Traduci (Cmd+Shift+Y)")
```
→
```swift
                        Text(String(localized: "menu.translate"))
```

```swift
                        Text("Writing Coach (Cmd+Shift+C)")
```
→
```swift
                        Text(String(localized: "menu.coach"))
```

```swift
                        Text("Preferenze...")
```
→
```swift
                        Text(String(localized: "menu.preferences"))
```

```swift
                        Text("Esci")
```
→
```swift
                        Text(String(localized: "menu.quit"))
```

- [ ] **Step 3: Modifica `App/AppDelegate.swift`**

Nel metodo `detectOllama()`, sostituisci il blocco alert:

```swift
                alert.messageText = "Ollama non rilevato"
                alert.informativeText = "Il service è configurato per usare Ollama (localhost:11434), ma il server non risulta in esecuzione. Avvia Ollama o modifica il service nelle Preferenze."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
```

con:

```swift
                alert.messageText = String(localized: "alert.ollama.title")
                alert.informativeText = String(localized: "alert.ollama.body")
                alert.alertStyle = .warning
                alert.addButton(withTitle: String(localized: "alert.ok"))
```

Nel metodo `warnFailedShortcuts()`, sostituisci:

```swift
        alert.messageText = "Scorciatoie non disponibili"
        alert.informativeText = "Le seguenti scorciatoie sono già in uso:\n\(failed.joined(separator: ", "))\n\nModificale nelle Preferenze."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
```

con:

```swift
        alert.messageText = String(localized: "alert.shortcuts.title")
        alert.informativeText = String(format: String(localized: "alert.shortcuts.body_format"), failed.joined(separator: ", "))
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "alert.ok"))
```

Nel metodo `showOnboardingIfFirstLaunch()`, sostituisci:

```swift
        window.title = "Benvenuto"
```

con:

```swift
        window.title = String(localized: "alert.window.welcome")
```

- [ ] **Step 4: Verifica build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Atteso: `Build complete!` senza errori.

- [ ] **Step 5: Commit**

```bash
git add UI/OnboardingView.swift UI/MenuBarView.swift App/AppDelegate.swift
git commit -m "feat(l10n): localize OnboardingView, MenuBarView, AppDelegate"
```

---

## Task 5: Localizza SuggestionView, FloatingEditor, GeneralTab, ModelCatalog

**Files:**
- Modify: `UI/SuggestionView.swift`
- Modify: `UI/FloatingEditor.swift`
- Modify: `UI/GeneralTab.swift`
- Modify: `Infra/ModelCatalog.swift`

- [ ] **Step 1: Modifica `UI/SuggestionView.swift`**

Nel metodo `toneLabel` (riga 112-124), sostituisci l'intero switch:

```swift
    private var toneLabel: String? {
        guard let tone = result?.detectedTone, !tone.isEmpty else { return nil }
        let display: String
        switch tone {
        case "formal":    display = String(localized: "suggestion.tone.formal")
        case "informal":  display = String(localized: "suggestion.tone.informal")
        case "neutral":   display = String(localized: "suggestion.tone.neutral")
        case "academic":  display = String(localized: "suggestion.tone.academic")
        case "technical": display = String(localized: "suggestion.tone.technical")
        default:          display = tone.capitalized
        }
        return "\(String(localized: "suggestion.tone.detected_prefix")) \(display)"
    }
```

Nel metodo `headerTitle` (riga 162-172), sostituisci:

```swift
    private var headerTitle: String {
        switch state {
        case .loading:           return String(localized: "suggestion.header.analyzing")
        case .streaming:         return String(localized: "suggestion.header.correcting")
        case .suggestion:        return String(localized: "suggestion.header.suggestion")
        case .fluencySuggestion: return String(localized: "suggestion.header.fluency")
        case .noErrors:          return String(localized: "suggestion.header.no_errors")
        case .error:             return String(localized: "suggestion.header.error")
        case .textTooLong:       return String(localized: "suggestion.header.too_long")
        }
    }
```

- [ ] **Step 2: Modifica `UI/FloatingEditor.swift`**

Nel `CheckMode` enum (righe 60-63), sostituisci:

```swift
    enum CheckMode: String, CaseIterable {
        case grammar = "grammar"
        case fluency = "fluency"

        var localizedName: String {
            switch self {
            case .grammar: return String(localized: "editor.mode.grammar")
            case .fluency: return String(localized: "editor.mode.fluency")
            }
        }
    }
```

Nel Picker (riga 69), sostituisci `Text(mode.rawValue)` con `Text(mode.localizedName)`.

Sostituisci `Text("Originale")`:

```swift
                    Text(String(localized: "editor.panel.original"))
```

Sostituisci `Text("Corretto")`:

```swift
                    Text(String(localized: "editor.panel.corrected"))
```

Sostituisci `Text("Il testo corretto apparirà qui")`:

```swift
                            Text(String(localized: "editor.placeholder"))
```

Sostituisci il bottone check (righe 140-150):

```swift
                Button(action: { checkText() }) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 16)
                        Text(String(localized: "editor.button.checking"))
                    } else {
                        Text(String(localized: "editor.button.check"))
                    }
                }
```

Sostituisci `Button("Copia")`:

```swift
                Button(String(localized: "editor.button.copy")) {
```

- [ ] **Step 3: Modifica `UI/GeneralTab.swift`**

Sostituisci `Section("Correttore (Cmd+Shift+E)")`:

```swift
            Section(String(localized: "prefs.section.corrector")) {
```

Sostituisci `Section("Fluency (Cmd+Shift+T)")`:

```swift
            Section(String(localized: "prefs.section.fluency_service")) {
```

Nel Section "Stato Server", sostituisci:

```swift
                    Text(serverIsRunning ? "llama-server: attivo" : "llama-server: fermo")
```

con:

```swift
                    Text(serverIsRunning
                        ? String(localized: "prefs.server.running")
                        : String(localized: "prefs.server.stopped"))
```

- [ ] **Step 4: Modifica `Infra/ModelCatalog.swift`**

Sostituisci le tre `reason:` strings nell'array `all`:

```swift
        ModelRecommendation(
            id: "qwen2.5-1.5b-instruct-q4_k_m",
            name: "Qwen 2.5 1.5B",
            reason: String(localized: "model.qwen.reason"),
            ...
        ),
        ModelRecommendation(
            id: "gemma-4-E2B-it-q4_k_m",
            name: "Gemma 4 E2B IT (5B)",
            reason: String(localized: "model.gemma2b.reason"),
            ...
        ),
        ModelRecommendation(
            id: "gemma-4-E4B-it-q4_k_m",
            name: "Gemma 4 E4B IT (8B)",
            reason: String(localized: "model.gemma4b.reason"),
            ...
        ),
```

Nota: `String(localized:)` in un contesto non-MainActor usa `Bundle.main` con la lingua di sistema. Poiché `ModelCatalog.all` è una variabile statica che viene valutata lazily, viene valutata al primo accesso (tipicamente già sul main thread via UI). Questo è corretto.

- [ ] **Step 5: Verifica build pulito + test**

```bash
swift build 2>&1 | grep -E "error:|Build complete" && swift test 2>&1 | tail -10
```

Atteso: `Build complete!` + tutti i test PASS.

- [ ] **Step 6: Commit**

```bash
git add UI/SuggestionView.swift UI/FloatingEditor.swift UI/GeneralTab.swift Infra/ModelCatalog.swift
git commit -m "feat(l10n): localize SuggestionView, FloatingEditor, GeneralTab, ModelCatalog"
```

---

## Task 6: Test finale di integrazione — build .app con localizzazione

**Files:**
- Nessun file di codice nuovo

- [ ] **Step 1: Build .app**

```bash
cd /Users/eugeniozamengopontrelli/Desktop/RefineClone && ./build-app.sh release 2>&1 | tail -20
```

Atteso: `[✓] RefineClone.app pronto.`

- [ ] **Step 2: Verifica che le directory .lproj siano nel bundle**

```bash
ls RefineClone.app/Contents/Resources/
```

Atteso: `en.lproj  it.lproj  zh-Hans.lproj  hr.lproj  da.lproj  nb.lproj  el.lproj` (più eventuale `Info.plist`).

- [ ] **Step 3: Verifica che i file .strings siano nelle directory giuste**

```bash
ls RefineClone.app/Contents/Resources/en.lproj/ && ls RefineClone.app/Contents/Resources/it.lproj/
```

Atteso: `Localizable.strings` in entrambe le directory.

- [ ] **Step 4: Esegui tutti i test**

```bash
swift test 2>&1 | tail -10
```

Atteso: tutti i test PASS.

- [ ] **Step 5: Commit finale**

```bash
git add -A
git commit -m "feat: UI localization complete — 7 languages, auto detection, universal rules"
```
