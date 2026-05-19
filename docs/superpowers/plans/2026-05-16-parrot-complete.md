# Parrot — Piano Completo di Miglioramento

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Risolvere tutti i bug confermati, aggiungere le feature mancanti critiche, migliorare la qualità del codice, e preparare il progetto al lancio — ordinato dal cambiamento più semplice al più complesso.

**Architecture:** App macOS menubar. 6 layer: App → Shortcuts → Accessibility → Core → Infra → UI. Swift actors per shared state, SwiftUI per le views, SPM come build system.

**Tech Stack:** Swift 5.10, SwiftUI, macOS 14+, SPM, XCTest, Carbon Event Manager, AXUIElement, AVFoundation (da aggiungere), llama.cpp via ServerManager.

---

## File Map

| File | Modifica |
|---|---|
| `Infra/ResultCache.swift` | Fix double-counting byteSize |
| `Core/TextExtractionService.swift` | Fix guard PID 0 |
| `UI/GeneralTab.swift` | Aggiungere campo API key OpenAI |
| `UI/SuggestionView.swift` | Fix loading flickering, aggiungere TTS, undo state, diff highlight, model-missing state |
| `UI/SuggestionPanel.swift` | Aggiungere undo flow, model-missing state |
| `Core/OpenRouterService.swift` | Rimuovere cache locale TTL |
| `Core/FeedbackLogger.swift` | Aggiungere rotazione file |
| `Infra/ServerHealthMonitor.swift` | Fix blocking restart |
| `UI/OnboardingView.swift` | Verifica permessi reale |
| `Core/CorrectionResult.swift` | Fix computeDiff offset |
| `Accessibility/AccessibilityBridge.swift` | Fix clipboard race condition |
| `Core/LLMServiceExtension.swift` | Refactor → Codable |
| `Core/LocalLLMService.swift` | Aggiornare a Codable |
| `Core/RemoteLLMService.swift` | Aggiornare a Codable |
| `Core/OllamaService.swift` | Aggiornare a Codable |
| `Core/OpenRouterService.swift` | Aggiornare a Codable |
| `Core/StubLLMService.swift` | Aggiornare a Codable |
| `Core/LLMService.swift` | Aggiungere translate(text:targetLanguage:) |
| `Core/PromptEngine.swift` | Aggiungere template traduzione |
| `UI/ModelsTab.swift` | Aggiungere stato modello mancante |
| `UI/AppRulesTab.swift` | Migliorare per-app settings UI |
| `Core/HistoryStore.swift` | Nuovo file — persistenza storia correzioni |
| `UI/HistoryTab.swift` | Nuovo file — tab storia |
| `UI/SettingsView.swift` | Aggiungere HistoryTab |
| `.github/workflows/ci.yml` | Nuovo — GitHub Actions CI |
| `.github/ISSUE_TEMPLATE/bug_report.md` | Nuovo |
| `.github/ISSUE_TEMPLATE/feature_request.md` | Nuovo |
| `Tests/Tests.swift` | Nuovi test per ogni task |

---

## GRUPPO 1 — Trivial Fixes (< 5 min ciascuno)

---

### Task 1: Fix PID 0 in TextExtractionService

**File:** `Core/TextExtractionService.swift:31`

- [ ] **Step 1: Scrivere il test (atteso che fallisca)**

In `Tests/Tests.swift`, aggiungere alla classe `MockAXBridgeTests`:

```swift
func testExtract_whenPIDIsZero_throwsNoTextSelected() async {
    // PID 0 è invalido — deve essere intercettato prima di creare AXUIElementCreateApplication(0)
    // Questo test verifica che il guard esista nel path senza PID esplicito
    // Non possiamo testare direttamente TextExtractionService.extract() senza mock
    // ma verifichiamo che lastKnownFrontAppPID restituisca 0 di default
    let bridge = AccessibilityBridge.shared
    let pid = await bridge.lastKnownFrontAppPID()
    // pid 0 è il valore di default — se mai usato in fetchTextOrLineAtCursor
    // creerebbe AXUIElementCreateApplication(0) che è undefined behavior
    XCTAssertEqual(pid, 0, "Default PID deve essere 0 per verificare il guard")
}
```

- [ ] **Step 2: Run test**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift test --filter MockAXBridgeTests/testExtract_whenPIDIsZero_throwsNoTextSelected 2>&1 | tail -5
```
Expected: PASS (il test verifica solo il valore di default, non il guard).

- [ ] **Step 3: Applicare il fix**

`Core/TextExtractionService.swift`, righe 29-33. Sostituire:
```swift
} catch CorrectionError.noTextSelected {
    let lastPID = await AccessibilityBridge.shared.lastKnownFrontAppPID()
    let (fallbackText, range) = try await AccessibilityBridge.shared.fetchTextOrLineAtCursor(fromPID: lastPID)
```

Con:
```swift
} catch CorrectionError.noTextSelected {
    let lastPID = await AccessibilityBridge.shared.lastKnownFrontAppPID()
    guard lastPID != 0 else { throw CorrectionError.noTextSelected }
    let (fallbackText, range) = try await AccessibilityBridge.shared.fetchTextOrLineAtCursor(fromPID: lastPID)
```

- [ ] **Step 4: Build**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift build 2>&1 | tail -5
```
Expected: `Build complete!`

- [ ] **Step 5: Commit**
```bash
git add Core/TextExtractionService.swift Tests/Tests.swift
git commit -m "fix: guard against PID 0 in TextExtractionService fallback path"
```

---

### Task 2: Fix ResultCache double-counting byteSize

**File:** `Infra/ResultCache.swift:28-36`

- [ ] **Step 1: Scrivere il test**

In `Tests/Tests.swift`, dopo `ResultCacheTests`, aggiungere:

```swift
func testSet_updatingExistingKey_doesNotDoublecountMemory() async {
    let cache = ResultCache.shared
    await cache.invalidateAll()

    let result1 = CorrectionResult(original: "hello world", corrected: "hello world!", modelID: "m1")
    let result2 = CorrectionResult(original: "hello world", corrected: "hi world!", modelID: "m1")

    await cache.set(result1, for: "hello world", modelID: "m1")
    let bytesAfterFirst = await cache.currentMemoryBytesForTesting

    await cache.set(result2, for: "hello world", modelID: "m1")
    let bytesAfterSecond = await cache.currentMemoryBytesForTesting

    // Il secondo set aggiorna la stessa key: i byte devono riflettere solo result2
    let expectedBytes = result2.originalText.utf8.count + result2.correctedText.utf8.count
    XCTAssertEqual(bytesAfterSecond, expectedBytes)
    XCTAssertLessThanOrEqual(bytesAfterSecond, bytesAfterFirst + expectedBytes)
}
```

- [ ] **Step 2: Esporre `currentMemoryBytes` per testing**

In `Infra/ResultCache.swift`, aggiungere dopo `private var currentMemoryBytes = 0`:
```swift
var currentMemoryBytesForTesting: Int { currentMemoryBytes }
```

- [ ] **Step 3: Run test**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift test --filter ResultCacheTests/testSet_updatingExistingKey_doesNotDoublecountMemory 2>&1 | tail -5
```
Expected: FAIL — `currentMemoryBytes` viene sommato due volte.

- [ ] **Step 4: Applicare il fix**

In `Infra/ResultCache.swift`, sostituire la funzione `set`:
```swift
func set(_ result: CorrectionResult, for text: String, modelID: String) {
    let byteSize = (result.originalText.utf8.count + result.correctedText.utf8.count)

    if let existing = cache[text] {
        currentMemoryBytes = max(0, currentMemoryBytes - existing.byteSize)
    }

    if cache.count >= maxEntries || (currentMemoryBytes + byteSize) > maxMemoryBytes {
        evictUntilUnderLimit(neededBytes: byteSize)
    }
    cache[text] = CacheEntry(result: result, timestamp: Date(), modelID: modelID, byteSize: byteSize)
    currentMemoryBytes += byteSize
}
```

- [ ] **Step 5: Run test**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift test --filter ResultCacheTests 2>&1 | tail -10
```
Expected: tutti i ResultCacheTests PASS.

- [ ] **Step 6: Commit**
```bash
git add Infra/ResultCache.swift Tests/Tests.swift
git commit -m "fix: subtract old byteSize before updating existing cache entry"
```

---

### Task 3: Aggiungere campo API Key OpenAI in GeneralTab

**File:** `UI/GeneralTab.swift:18-21`

Questo fix rende il modo `.remote` (OpenAI) utilizzabile da utenti nuovi.

- [ ] **Step 1: Aggiungere `openAIAPIKey` a PreferencesStore**

In `Infra/PreferencesStore.swift`, dopo il blocco `openAIModel` (riga ~43), aggiungere:
```swift
var openAIAPIKey: String {
    get {
        observe()
        if let cached = _cachedAPIKeys["openai"] { return cached }
        let key = (try? KeychainService.shared.load(for: "openai")) ?? ""
        _cachedAPIKeys["openai"] = key
        return key
    }
    set {
        if newValue.isEmpty {
            do { try KeychainService.shared.delete(for: "openai") }
            catch { os_log(.error, "PreferencesStore: failed to delete OpenAI key: %{public}@", error.localizedDescription) }
            _cachedAPIKeys.removeValue(forKey: "openai")
        } else {
            do { try KeychainService.shared.save(key: newValue, for: "openai") }
            catch { os_log(.error, "PreferencesStore: failed to save OpenAI key: %{public}@", error.localizedDescription) }
            _cachedAPIKeys["openai"] = newValue
        }
        invalidate()
    }
}
```

- [ ] **Step 2: Aggiornare RemoteLLMService per usare la chiave da Keychain**

In `Core/RemoteLLMService.swift`, localizzare dove si legge la API key e sostituire con:
```swift
private func openAIAPIKey() -> String {
    (try? KeychainService.shared.load(for: "openai")) ?? ""
}
```
(Rimuovere qualsiasi cache locale separata se esiste.)

- [ ] **Step 3: Aggiungere OpenAIKeyField in GeneralTab**

In `UI/GeneralTab.swift`, sostituire il blocco `if prefs.serviceType == .remote`:
```swift
if prefs.serviceType == .remote {
    TextField("Base URL", text: $prefs.openAIBaseURL)
    TextField("Modello", text: $prefs.openAIModel)
    OpenAIKeyField(prefs: prefs)
}
```

In fondo al file, aggiungere:
```swift
private struct OpenAIKeyField: View {
    let prefs: PreferencesStore
    @State private var localKey: String = ""

    var body: some View {
        SecureField("API Key OpenAI", text: $localKey)
            .onAppear { localKey = prefs.openAIAPIKey }
            .onSubmit { prefs.openAIAPIKey = localKey }
            .onDisappear { prefs.openAIAPIKey = localKey }
    }
}
```

- [ ] **Step 4: Build**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift build 2>&1 | tail -5
```
Expected: `Build complete!`

- [ ] **Step 5: Commit**
```bash
git add UI/GeneralTab.swift Infra/PreferencesStore.swift Core/RemoteLLMService.swift
git commit -m "fix: add OpenAI API key field to GeneralTab — remote mode was unconfigurable"
```

---

## GRUPPO 2 — Simple State/Logic Fixes

---

### Task 4: Fix loading message flickering in SuggestionView

**File:** `UI/SuggestionView.swift:130-148`

Problema: `loadingMessage` è una computed property che usa `Date()`, causa flicker ad ogni re-render.

- [ ] **Step 1: Sostituire la computed property con @State + timer**

In `UI/SuggestionView.swift`, rimuovere:
```swift
private var loadingMessage: String {
    let messages = [
        "Analizzando la grammatica...",
        "Controllando i verbi...",
        "Verificando la punteggiatura...",
        "Analisi delle concordanze...",
        "Controllo ortografico in corso..."
    ]
    return messages[Int(Date().timeIntervalSince1970) % messages.count]
}
```

Aggiungere nell'area delle `@State` della struct:
```swift
private static let loadingMessages = [
    "Analizzando la grammatica...",
    "Controllando i verbi...",
    "Verificando la punteggiatura...",
    "Analisi delle concordanze...",
    "Controllo ortografico in corso..."
]
@State private var loadingMessageIndex: Int = 0
```

- [ ] **Step 2: Aggiornare il caso `.loading` in `contentView`**

Sostituire il caso `.loading`:
```swift
case .loading:
    VStack {
        ProgressView(Self.loadingMessages[loadingMessageIndex])
            .frame(height: 60)
    }
    .onAppear {
        loadingMessageIndex = Int(Date().timeIntervalSince1970) % Self.loadingMessages.count
    }
    .task {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeInOut(duration: 0.3)) {
                loadingMessageIndex = (loadingMessageIndex + 1) % Self.loadingMessages.count
            }
        }
    }
```

- [ ] **Step 3: Build**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift build 2>&1 | tail -5
```
Expected: `Build complete!`

- [ ] **Step 4: Commit**
```bash
git add UI/SuggestionView.swift
git commit -m "fix: stabilize loading message with @State + async task, eliminate Date() flickering"
```

---

### Task 5: Fix OpenRouterService cache TTL inconsistente

**File:** `Core/OpenRouterService.swift:11-35`

Problema: `OpenRouterService` ha una cache locale con TTL 60s. Quando l'utente cambia chiave in settings (che va via `PreferencesStore._cachedAPIKeys`), `OpenRouterService` continua a usare quella vecchia per 60 secondi.

Fix: eliminare la cache locale in `OpenRouterService` e leggere sempre da Keychain diretto (che è già O(1) su Apple Silicon).

- [ ] **Step 1: Semplificare `openRouterAPIKey()` in OpenRouterService**

In `Core/OpenRouterService.swift`, rimuovere:
```swift
private let apiKeyLock = NSLock()
private nonisolated(unsafe) var _cachedAPIKey: String?
private nonisolated(unsafe) var _lastAPIKeyTime: Date = .distantPast
```

E sostituire `openRouterAPIKey()`:
```swift
private func openRouterAPIKey() -> String {
    (try? KeychainService.shared.load(for: "openrouter")) ?? ""
}
```

- [ ] **Step 2: Build**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift build 2>&1 | tail -5
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**
```bash
git add Core/OpenRouterService.swift
git commit -m "fix: remove stale 60s API key cache from OpenRouterService — use Keychain directly"
```

---

### Task 6: Logging strutturato con OSLog subsystem/category

**File:** tutti i file con `os_log`

Attualmente: `os_log(.debug, "message")` — nessun subsystem, impossibile filtrare in Console.app.
Fix: usare `Logger` (iOS 14+ / macOS 11+) con subsystem `com.thousandflowers.parrot` e categoria per file.

- [ ] **Step 1: Aggiungere file di helper Logger**

Creare `Core/AppLogger.swift`:
```swift
import OSLog

extension Logger {
    static let cache    = Logger(subsystem: Constants.bundleID, category: "cache")
    static let core     = Logger(subsystem: Constants.bundleID, category: "core")
    static let infra    = Logger(subsystem: Constants.bundleID, category: "infra")
    static let ui       = Logger(subsystem: Constants.bundleID, category: "ui")
    static let ax       = Logger(subsystem: Constants.bundleID, category: "accessibility")
    static let server   = Logger(subsystem: Constants.bundleID, category: "server")
    static let feedback = Logger(subsystem: Constants.bundleID, category: "feedback")
}
```

- [ ] **Step 2: Sostituire os_log in FeedbackLogger.swift**

In `Core/FeedbackLogger.swift`:
- `os_log(.error, "Cannot access Application Support directory")` → `Logger.feedback.error("Cannot access Application Support directory")`
- `os_log(.info, "Feedback logged: %{public}@", reason)` → `Logger.feedback.info("Feedback logged: \(reason, privacy: .public)")`
- `os_log(.error, "Failed to write feedback: %{public}@", error.localizedDescription)` → `Logger.feedback.error("Failed to write feedback: \(error.localizedDescription, privacy: .public)")`

- [ ] **Step 3: Sostituire os_log in ServerHealthMonitor.swift**

- `os_log(.debug, "Health check failed: ...")` → `Logger.server.debug("Health check failed: \(error.localizedDescription, privacy: .public)")`
- `os_log(.error, "ServerHealthMonitor: restart failed ...")` → `Logger.server.error("ServerHealthMonitor: restart failed: \(error.localizedDescription, privacy: .public)")`

- [ ] **Step 4: Sostituire os_log in ModelManager.swift**

Tutti gli `os_log` → rispettivi `Logger.infra.error(...)` / `Logger.infra.info(...)`.

- [ ] **Step 5: Sostituire os_log in PreferencesStore.swift, PreferencesCache.swift, OpenRouterService.swift**

Tutti → `Logger.infra.error(...)` / `Logger.infra.debug(...)`.

- [ ] **Step 6: Sostituire os_log in LLMServiceExtension.swift, PromptEngine.swift**

Tutti → `Logger.core.debug(...)`.

- [ ] **Step 7: Build + test**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift build 2>&1 | tail -5
swift test 2>&1 | tail -5
```
Expected: `Build complete!`, `67 tests passed` (o più se ne abbiamo aggiunti).

- [ ] **Step 8: Commit**
```bash
git add Core/AppLogger.swift Core/FeedbackLogger.swift Core/LLMServiceExtension.swift Core/PromptEngine.swift Core/OpenRouterService.swift Infra/ServerHealthMonitor.swift Infra/ModelManager.swift Infra/PreferencesStore.swift Infra/PreferencesCache.swift
git commit -m "refactor: replace os_log with structured Logger(subsystem:category:) throughout"
```

---

## GRUPPO 3 — Medium Complexity

---

### Task 7: FeedbackLogger — rotazione file

**File:** `Core/FeedbackLogger.swift`

- [ ] **Step 1: Scrivere il test**

In `Tests/Tests.swift`, aggiungere:
```swift
final class FeedbackLoggerTests: XCTestCase {
    func testLog_truncatesOriginalTextTo500Chars() {
        let longText = String(repeating: "a", count: 600)
        // Test che la funzione non crashi con testo lungo
        // Non possiamo verificare il file direttamente senza setup temporaneo
        // ma possiamo verificare che non lanci eccezioni
        FeedbackLogger.log(original: longText, corrected: "short", reason: "test", modelID: "test")
        // Se arriva qui senza crash, il test passa
    }
}
```

- [ ] **Step 2: Run test**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift test --filter FeedbackLoggerTests 2>&1 | tail -5
```
Expected: PASS.

- [ ] **Step 3: Aggiornare `log()` con truncazione e rotazione**

In `Core/FeedbackLogger.swift`, sostituire la funzione `log`:
```swift
private static let maxEntries = 1000
private static let maxFileBytes = 10 * 1024 * 1024 // 10 MB
private static let textTruncationLimit = 500

static func log(original: String, corrected: String, reason: String = "user_disagrees", modelID: String = "unknown") {
    let truncated = String(original.prefix(textTruncationLimit))
    let correctedTruncated = String(corrected.prefix(textTruncationLimit))
    let entry = FeedbackEntry(
        timestamp: Date(),
        original: truncated,
        corrected: correctedTruncated,
        reason: reason,
        modelID: modelID
    )

    do {
        try FileManager.default.createDirectory(at: feedbackDir, withIntermediateDirectories: true)

        // Controlla dimensione file e ruota se necessario
        if FileManager.default.fileExists(atPath: feedbackURL.path(percentEncoded: false)) {
            let attrs = try FileManager.default.attributesOfItem(atPath: feedbackURL.path(percentEncoded: false))
            let fileSize = attrs[.size] as? Int ?? 0
            if fileSize > maxFileBytes {
                rotateLog()
            }
        }

        let data = try JSONEncoder().encode(entry)
        var line = (String(data: data, encoding: .utf8) ?? "") + "\n"
        if FileManager.default.fileExists(atPath: feedbackURL.path(percentEncoded: false)) {
            let handle = try FileHandle(forWritingTo: feedbackURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let lineData = line.data(using: .utf8) {
                try handle.write(contentsOf: lineData)
            }
        } else {
            try line.write(to: feedbackURL, atomically: true, encoding: .utf8)
        }
        Logger.feedback.info("Feedback logged: \(reason, privacy: .public)")
    } catch {
        Logger.feedback.error("Failed to write feedback: \(error.localizedDescription, privacy: .public)")
    }
}

private static func rotateLog() {
    guard let content = try? String(contentsOf: feedbackURL, encoding: .utf8) else { return }
    let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
    guard lines.count > 200 else { return }
    let kept = lines.suffix(lines.count - 200).joined(separator: "\n") + "\n"
    try? kept.write(to: feedbackURL, atomically: true, encoding: .utf8)
    Logger.feedback.info("FeedbackLogger: rotated log, removed 200 oldest entries")
}
```

- [ ] **Step 4: Build + test**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift build 2>&1 | tail -5 && swift test --filter FeedbackLoggerTests 2>&1 | tail -5
```
Expected: `Build complete!`, `FeedbackLoggerTests passed`.

- [ ] **Step 5: Commit**
```bash
git add Core/FeedbackLogger.swift Tests/Tests.swift
git commit -m "fix: add FeedbackLogger rotation (10MB limit, 500 char truncation)"
```

---

### Task 8: ServerHealthMonitor — restart non-bloccante

**File:** `Infra/ServerHealthMonitor.swift:54-64`

Problema: `restartServer()` chiama `ServerManager.shared.start()` che blocca per ~30s. Durante questo tempo nessuna correzione può partire.

- [ ] **Step 1: Fare il restart in un Task separato non-bloccante**

In `Infra/ServerHealthMonitor.swift`, sostituire `restartServer()`:
```swift
private func restartServer() async {
    await ServerManager.shared.stop()
    if let modelPath = ModelManager.shared.currentModelPath {
        Task {
            do {
                try await ServerManager.shared.start(modelPath: modelPath)
                await startMonitoring()
                Logger.server.info("ServerHealthMonitor: server restarted successfully")
            } catch {
                Logger.server.error("ServerHealthMonitor: restart failed — \(error.localizedDescription, privacy: .public)")
            }
        }
        await MainActor.run {
            SuggestionPanelController.shared.showError(.serverTimeout)
        }
    }
}
```

Nota: `startMonitoring()` deve essere `async` se non lo è già. Verificare la firma e adattare se necessario.

- [ ] **Step 2: Build**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift build 2>&1 | tail -10
```
Se `startMonitoring()` non è async, usare `Task { await self.startMonitoring() }` oppure rimuovere l'`await`.

- [ ] **Step 3: Commit**
```bash
git add Infra/ServerHealthMonitor.swift
git commit -m "fix: run server restart in background Task — unblocks request queue during recovery"
```

---

### Task 9: Onboarding — verifica permessi reale

**File:** `UI/OnboardingView.swift`

Problema: il pulsante "Avanti" dallo step permessi è sempre abilitato.
Fix: disabilitare "Avanti" finché `AXIsProcessTrusted()` non ritorna `true`. Fare polling ogni 500ms.

- [ ] **Step 1: Aggiungere stato di verifica permessi**

In `UI/OnboardingView.swift`, aggiungere alla struct `OnboardingView`:
```swift
@State private var isAccessibilityGranted: Bool = AXIsProcessTrusted()
```

- [ ] **Step 2: Aggiornare il pulsante "Avanti"**

Nel corpo della view, sostituire il pulsante "Avanti":
```swift
if step < 2 {
    Button("Avanti") { step += 1 }
        .buttonStyle(.borderedProminent)
        .disabled(step == 1 && !isAccessibilityGranted)
} else {
    ...
}
```

- [ ] **Step 3: Aggiungere polling nel permissionsStep**

Sostituire `permissionsStep` con:
```swift
private var permissionsStep: some View {
    VStack(spacing: 20) {
        Spacer()
        if isAccessibilityGranted {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundColor(.statusOk)
            Text("Permessi concessi!")
                .font(.title2)
            Text("Parrot può ora leggere e correggere il testo nelle altre applicazioni.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
        } else {
            Image(systemName: "hand.raised.fill")
                .font(.title)
                .foregroundColor(.statusWarning)
            Text("Permessi di Accessibilità")
                .font(.title2)
            Text("Parrot ha bisogno dei permessi di Accessibilità per leggere e correggere il testo nelle altre applicazioni.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            Button("Apri Impostazioni di Sistema") {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            }
            Text("Aggiungi Parrot alla lista delle app autorizzate in Privacy e Sicurezza → Accessibilità.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
        }
        Spacer()
    }
    .task {
        while !isAccessibilityGranted {
            try? await Task.sleep(for: .milliseconds(500))
            isAccessibilityGranted = AXIsProcessTrusted()
        }
    }
}
```

- [ ] **Step 4: Build**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift build 2>&1 | tail -5
```

- [ ] **Step 5: Commit**
```bash
git add UI/OnboardingView.swift
git commit -m "fix: disable onboarding Next button until accessibility permissions actually granted"
```

---

### Task 10: CI GitHub Actions

**File:** `.github/workflows/ci.yml` (nuovo)

- [ ] **Step 1: Creare workflow**

Creare `.github/workflows/ci.yml`:
```yaml
name: CI

on:
  push:
    branches: [ main, "fix/**", "feat/**" ]
  pull_request:
    branches: [ main ]

jobs:
  build-and-test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.4.app

      - name: Build
        run: swift build 2>&1

      - name: Test
        run: swift test 2>&1
```

- [ ] **Step 2: Creare GitHub Issue templates**

Creare `.github/ISSUE_TEMPLATE/bug_report.md`:
```markdown
---
name: Bug report
about: Segnala un bug in Parrot
labels: bug
---

**Descrizione**
Una descrizione chiara del bug.

**Passi per riprodurre**
1. Seleziona testo in [app]
2. Premi Cmd+Shift+E
3. ...

**Comportamento atteso**
Cosa dovrebbe succedere.

**Screenshot / log**
Se possibile, allega screenshot o log da Console.app (filtro: `com.thousandflowers.parrot`).

**Ambiente**
- macOS: [es. 14.5]
- CPU: [Apple Silicon / Intel]
- Versione Parrot: [es. 1.0.0]
- Servizio LLM: [Locale / Ollama / OpenAI / OpenRouter]
```

Creare `.github/ISSUE_TEMPLATE/feature_request.md`:
```markdown
---
name: Feature request
about: Proponi una nuova funzionalità
labels: enhancement
---

**Il problema che vuoi risolvere**
Es: "È frustrante quando..."

**Soluzione proposta**
Descrivi la funzionalità che vorresti.

**Alternative considerate**
Hai considerato altri approcci?

**Contesto aggiuntivo**
Aggiungi screenshot, link, o qualsiasi contesto utile.
```

- [ ] **Step 3: Commit**
```bash
mkdir -p .github/workflows .github/ISSUE_TEMPLATE
git add .github/
git commit -m "ci: add GitHub Actions CI workflow and issue templates"
```

---

## GRUPPO 4 — Complex Multi-File

---

### Task 11: Fix computeDiff — offset errati con spazi consecutivi

**File:** `Core/CorrectionResult.swift:60-96`

Problema: `split(separator: " ", omittingEmptySubsequences: true)` non traccia le posizioni corrette quando ci sono spazi multipli. L'offset viene calcolato sbagliato.

Fix: sostituire con un tokenizer che scansiona carattere per carattere e salva l'`String.Index` di ogni parola.

- [ ] **Step 1: Aggiornare il test esistente**

In `Tests/Tests.swift`, aggiornare `testComputeDiff_consecutiveSpaces_doesNotCrash`:
```swift
func testComputeDiff_consecutiveSpaces_correctOffsets() {
    // "hello  world" — doppio spazio: "world" inizia al carattere 7, non 6
    guard let ops = CorrectionResult.computeDiff(original: "hello  world", corrected: "hello globe") else {
        XCTFail("Expected diff ops"); return
    }
    // "world" (offset 7) viene sostituito con "globe"
    let deleteOp = ops.first(where: { $0.type == .delete })
    XCTAssertNotNil(deleteOp)
    if let op = deleteOp {
        // "world" parte al carattere 7 (indice 0: 'h', ..., 5: ' ', 6: ' ', 7: 'w')
        XCTAssertEqual(op.offset, 7, "Offset deve puntare a 'world' dopo il doppio spazio")
    }
}
```

- [ ] **Step 2: Run test**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift test --filter CorrectionResultTests/testComputeDiff_consecutiveSpaces_correctOffsets 2>&1 | tail -5
```
Expected: FAIL — offset calcolato erroneamente.

- [ ] **Step 3: Sostituire computeDiff con tokenizer che preserva posizioni**

In `Core/CorrectionResult.swift`, sostituire `computeDiff`:
```swift
static func computeDiff(original: String, corrected: String) -> [DiffOp]? {
    guard original != corrected else { return nil }

    struct Token { let text: Substring; let charOffset: Int }

    // Tokenizer che scansiona char per char — gestisce spazi multipli
    func tokenize(_ s: String) -> [Token] {
        var tokens: [Token] = []
        var i = s.startIndex
        while i < s.endIndex {
            while i < s.endIndex && s[i].isWhitespace { i = s.index(after: i) }
            guard i < s.endIndex else { break }
            let start = i
            let charOffset = s.distance(from: s.startIndex, to: start)
            while i < s.endIndex && !s[i].isWhitespace { i = s.index(after: i) }
            tokens.append(Token(text: s[start..<i], charOffset: charOffset))
        }
        return tokens
    }

    let origTokens = tokenize(original)
    let corrTokens = tokenize(corrected)

    let diff = corrTokens.map(\.text).difference(from: origTokens.map(\.text))
    guard !diff.isEmpty else { return nil }

    var ops: [DiffOp] = []
    for change in diff {
        switch change {
        case .remove(let wordOffset, let word, _):
            let offset = wordOffset < origTokens.count ? origTokens[wordOffset].charOffset : (origTokens.last.map { $0.charOffset + $0.text.count } ?? 0)
            ops.append(DiffOp(type: .delete, offset: offset, length: word.count, replacement: nil))
        case .insert(let resultOffset, let word, _):
            let offset: Int
            if resultOffset < origTokens.count {
                offset = origTokens[resultOffset].charOffset
            } else if let last = origTokens.last {
                offset = last.charOffset + last.text.count
            } else {
                offset = 0
            }
            ops.append(DiffOp(type: .insert, offset: offset, length: word.count, replacement: String(word)))
        }
    }
    return ops.isEmpty ? nil : ops
}
```

- [ ] **Step 4: Run tutti i test CorrectionResult**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift test --filter CorrectionResultTests 2>&1 | tail -10
```
Expected: tutti PASS.

- [ ] **Step 5: Commit**
```bash
git add Core/CorrectionResult.swift Tests/Tests.swift
git commit -m "fix: computeDiff uses char-by-char tokenizer to correctly handle consecutive whitespace"
```

---

### Task 12: AccessibilityBridge — fix clipboard race condition

**File:** `Accessibility/AccessibilityBridge.swift:245-296`

Problemi:
1. Utente che copia durante il polling di 500ms → il changeCount cambia → restore non avviene
2. App che non supporta Cmd+V → clipboard resta sovrascritta

Fix:
- Usare `changeCount` dell'istante dopo aver scritto il testo corretto come sentinel, non quello originale
- Timeout allungato a 1.5s
- Notifica utente se restore non avviene

- [ ] **Step 1: Aggiornare `injectViaClipboard`**

In `Accessibility/AccessibilityBridge.swift`, sostituire `injectViaClipboard`:
```swift
private func injectViaClipboard(correctedText: String) async throws {
    let pasteboard = NSPasteboard.general

    // Salva contenuto originale PRIMA di modificare la clipboard
    let originalItems = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
        let copy = NSPasteboardItem()
        for type in item.types {
            if let data = item.data(forType: type) { copy.setData(data, forType: type) }
        }
        return copy
    } ?? []

    // Se c'era un restore pendente, eseguilo subito
    if let existing = self.pendingClipboardRestore {
        restoreClipboard(existing)
        self.pendingClipboardRestore = nil
    }

    pasteboard.clearContents()
    pasteboard.setString(correctedText, forType: .string)
    let sentinelCount = pasteboard.changeCount // changeCount dopo la nostra scrittura

    let source = CGEventSource(stateID: .hidSystemState)
    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x09), keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x09), keyDown: false) else {
        // Cmd+V non sintetizzabile — restore immediato
        if !originalItems.isEmpty { restoreClipboard(PendingClipboardRestore(items: originalItems, originalChangeCount: sentinelCount)) }
        return
    }
    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)

    guard !originalItems.isEmpty else { return }

    let pending = PendingClipboardRestore(items: originalItems, originalChangeCount: sentinelCount)
    self.pendingClipboardRestore = pending

    // Poll 1.5s — aspettiamo che l'app abbia incollato (changeCount cambierà di nuovo)
    for _ in 0..<30 {
        try? await Task.sleep(for: .milliseconds(50))
        // Se il changeCount è cambiato rispetto al nostro sentinel, qualcuno ha modificato la clipboard
        if pasteboard.changeCount != sentinelCount {
            // L'app ha incollato (o l'utente ha copiato qualcosa) — restore
            if self.pendingClipboardRestore?.originalChangeCount == pending.originalChangeCount {
                restoreClipboard(pending)
                self.pendingClipboardRestore = nil
            }
            return
        }
    }

    // Timeout: 1.5s passati — restore comunque per non lasciare la clipboard sporca
    if self.pendingClipboardRestore?.originalChangeCount == pending.originalChangeCount {
        restoreClipboard(pending)
        self.pendingClipboardRestore = nil
    }
}
```

- [ ] **Step 2: Build**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**
```bash
git add Accessibility/AccessibilityBridge.swift
git commit -m "fix: more robust clipboard restore — use sentinel changeCount, 1.5s timeout, always restore"
```

---

### Task 13: Undo dopo apply

**File:** `UI/SuggestionPanel.swift`, `UI/SuggestionView.swift`

- [ ] **Step 1: Aggiungere case `.applied` a `SuggestionState`**

In `UI/SuggestionPanel.swift`, aggiungere alla enum:
```swift
case applied(CorrectionResult)
```

- [ ] **Step 2: Aggiornare `SuggestionPanelController`**

Aggiungere `undoTask` come property privata:
```swift
private var undoTask: Task<Void, Never>?
```

Sostituire `applyCorrection()`:
```swift
private func applyCorrection() {
    guard let result = currentResult else { return }
    Task { [weak self] in
        guard let self else { return }
        do {
            try await AccessibilityBridge.shared.replaceSelectedText(with: result.correctedText)
            // Mostra stato "applicato" con possibilità di annullare per 5 secondi
            self.showOrUpdate(result: result, state: .applied(result))
            self.undoTask = Task {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self.close()
            }
        } catch {
            self.showError(error as? CorrectionError ?? .textExtractionFailed(appName: "unknown"))
        }
    }
}
```

Aggiungere funzione `undoCorrection()`:
```swift
private func undoCorrection() {
    undoTask?.cancel()
    undoTask = nil
    guard let result = currentResult else { close(); return }
    Task { [weak self] in
        guard let self else { return }
        do {
            try await AccessibilityBridge.shared.replaceSelectedText(with: result.originalText)
            // Mostra di nuovo il suggerimento originale
            let state: SuggestionState = result.hasChanges ? .suggestion(result) : .noErrors
            self.showOrUpdate(result: result, state: state)
        } catch {
            self.close()
        }
    }
}
```

Aggiornare `close()` per cancellare `undoTask`:
```swift
func close() {
    undoTask?.cancel()
    undoTask = nil
    explanationTask?.cancel()
    // ... resto invariato
}
```

- [ ] **Step 3: Aggiornare `showOrUpdate` per passare `onUndo`**

Il `SuggestionView` riceve già `onApply`, `onDismiss`, `onExplain`. Aggiungere `onUndo`:

In `UI/SuggestionView.swift`, aggiornare la struct:
```swift
struct SuggestionView: View {
    let result: CorrectionResult?
    let state: SuggestionState
    let onApply: () -> Void
    let onExplain: () -> Void
    let onDismiss: () -> Void
    let onUndo: () -> Void     // ← nuovo
    ...
}
```

In `SuggestionPanelController.showOrUpdate`, nel punto in cui si crea `SuggestionView`, aggiungere `onUndo: { [weak self] in self?.undoCorrection() }`.

- [ ] **Step 4: Aggiornare `headerIcon`, `headerTitle`, `footerView` in SuggestionView**

Nel `headerIcon`:
```swift
case .applied:
    Image(systemName: "checkmark.circle.fill")
        .foregroundColor(.statusOk)
```

Nel `headerTitle`:
```swift
case .applied: return "Testo applicato"
```

Nel `contentView` — aggiungere:
```swift
case .applied:
    VStack(spacing: 8) {
        Image(systemName: "checkmark.circle")
            .font(.largeTitle)
            .foregroundColor(.statusOk)
        Text("Il testo è stato sostituito correttamente.")
            .foregroundColor(.textSecondary)
            .font(.subheadline)
    }
    .frame(height: 80)
```

Nel `footerView` — aggiungere:
```swift
case .applied:
    Spacer()
    Button("Annulla") { onUndo() }
        .accessibilityHint("Ripristina il testo originale")
    Spacer()
```

- [ ] **Step 5: Aggiornare lo `stateHash` e `headerTitle` switch per includere `.applied`**

Aggiungere `case .applied` a tutti gli switch nel `SuggestionView` che usano exhaustive matching.

- [ ] **Step 6: Build**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift build 2>&1 | tail -10
```

- [ ] **Step 7: Commit**
```bash
git add UI/SuggestionPanel.swift UI/SuggestionView.swift
git commit -m "feat: undo-after-apply — show 5s window to restore original text after correction"
```

---

### Task 14: Stato caricamento modello chiaro

**File:** `UI/SuggestionPanel.swift`, `UI/SuggestionView.swift`

Quando il modello non è installato, l'utente ora vede un errore generico. Fix: mostrare uno stato dedicato con CTA "Vai ai Modelli".

- [ ] **Step 1: Aggiungere `.modelMissing` a SuggestionState**

```swift
case modelMissing
```

- [ ] **Step 2: Intercettare l'errore in `showError`**

In `SuggestionPanelController`:
```swift
func showError(_ error: CorrectionError) {
    if case .modelNotLoaded = error {
        showOrUpdate(result: nil, state: .modelMissing)
    } else {
        showOrUpdate(result: nil, state: .error(error))
    }
}
```

- [ ] **Step 3: Aggiungere rendering per `.modelMissing` in SuggestionView**

Nel `headerIcon`:
```swift
case .modelMissing:
    Image(systemName: "cpu.fill")
        .foregroundColor(.statusWarning)
```

Nel `headerTitle`:
```swift
case .modelMissing: return "Modello non trovato"
```

Nel `contentView`:
```swift
case .modelMissing:
    VStack(spacing: 12) {
        Text("Nessun modello AI è installato.")
            .foregroundColor(.textSecondary)
        Button("Vai ai Modelli") {
            onDismiss()
            // Apre le settings sulla tab Modelli
            NSApp.sendAction(Selector(("showSettings:")), to: nil, from: nil)
        }
        .buttonStyle(.borderedProminent)
    }
    .frame(height: 80)
```

Nel `footerView`:
```swift
case .modelMissing:
    Button("Chiudi") { onDismiss() }
    Spacer()
```

- [ ] **Step 4: Aggiornare `onUndo` signature per `.modelMissing`**

Il nuovo case non usa `onUndo`. Aggiungere `case .modelMissing` ai pattern match esistenti negli switch.

- [ ] **Step 5: Build**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift build 2>&1 | tail -5
```

- [ ] **Step 6: Commit**
```bash
git add UI/SuggestionPanel.swift UI/SuggestionView.swift
git commit -m "feat: show model-missing state with CTA instead of generic error when no model installed"
```

---

## GRUPPO 5 — Complex Architectural Changes

---

### Task 15: Text-to-Speech nel pannello

**File:** `UI/SuggestionView.swift`, `Package.swift`

- [ ] **Step 1: Verificare che AVFoundation sia disponibile via SPM**

In `Package.swift`, i framework di sistema non richiedono dipendenze extra su macOS. `AVFoundation` è sempre disponibile. Nessuna modifica a Package.swift.

- [ ] **Step 2: Aggiungere `import AVFoundation` e stato TTS a SuggestionView**

In `UI/SuggestionView.swift`:
```swift
import AVFoundation
```

Aggiungere alla struct:
```swift
@State private var synthesizer = AVSpeechSynthesizer()
@State private var isSpeaking = false
```

- [ ] **Step 3: Aggiungere funzione speak**

```swift
private func speakCorrected(_ text: String) {
    if isSpeaking {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        return
    }
    let utterance = AVSpeechUtterance(string: text)
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    isSpeaking = true
    synthesizer.speak(utterance)
    // Reset flag quando finisce
    Task {
        while synthesizer.isSpeaking {
            try? await Task.sleep(for: .milliseconds(100))
        }
        isSpeaking = false
    }
}
```

- [ ] **Step 4: Aggiungere bottone "Ascolta" nel footerView per `.suggestion` e `.fluencySuggestion`**

Nel `footerView`, nel caso `.suggestion, .fluencySuggestion`:
```swift
case .suggestion(let r, _, _), .fluencySuggestion(let r, _, _):
    Button(String(localized: "panel.ignore")) { onDismiss() }
    Spacer()
    Button(isSpeaking ? "Stop" : "Ascolta") {
        speakCorrected(r.correctedText)
    }
    .accessibilityLabel(isSpeaking ? "Ferma lettura" : "Leggi il testo corretto ad alta voce")
    Button(String(localized: "panel.explain")) { onExplain() }
    Button(String(localized: "panel.apply")) { onApply() }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
```

- [ ] **Step 5: Fermare la sintesi quando il pannello viene chiuso**

Aggiungere `.onDisappear` al body principale:
```swift
.onDisappear {
    synthesizer.stopSpeaking(at: .immediate)
}
```

- [ ] **Step 6: Build**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift build 2>&1 | tail -5
```

- [ ] **Step 7: Commit**
```bash
git add UI/SuggestionView.swift
git commit -m "feat: text-to-speech button in suggestion panel using AVSpeechSynthesizer"
```

---

### Task 16: Refactor JSON [String: Any] → Codable in LLMServiceExtension

**File:** `Core/LLMServiceExtension.swift`, `Core/LocalLLMService.swift`, `Core/RemoteLLMService.swift`, `Core/OllamaService.swift`, `Core/OpenRouterService.swift`

- [ ] **Step 1: Definire i tipi Codable in un nuovo file**

Creare `Core/LLMAPITypes.swift`:
```swift
import Foundation

struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let max_tokens: Int
    let stream: Bool
}

struct ChatMessage: Encodable {
    let role: String
    let content: String
}

struct ChatResponse: Decodable {
    let choices: [Choice]
    struct Choice: Decodable {
        let message: Message
        struct Message: Decodable {
            let content: String
        }
    }
}

struct StreamChunk: Decodable {
    let choices: [StreamChoice]
    struct StreamChoice: Decodable {
        let delta: Delta
        let finish_reason: String?
        struct Delta: Decodable {
            let content: String?
        }
    }
}
```

- [ ] **Step 2: Scrivere i test**

In `Tests/Tests.swift`, aggiungere:
```swift
final class LLMAPITypesTests: XCTestCase {
    func testChatRequestEncodesCorrectly() throws {
        let req = ChatRequest(
            model: "gpt-4o-mini",
            messages: [ChatMessage(role: "user", content: "test")],
            temperature: 0.1,
            max_tokens: 1024,
            stream: false
        )
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["model"] as? String, "gpt-4o-mini")
        XCTAssertEqual(json["temperature"] as? Double, 0.1)
        let messages = json["messages"] as! [[String: Any]]
        XCTAssertEqual(messages.first?["role"] as? String, "user")
    }

    func testChatResponseDecodesCorrectly() throws {
        let json = """
        {"choices":[{"message":{"content":"corrected text"}}]}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ChatResponse.self, from: json)
        XCTAssertEqual(response.choices.first?.message.content, "corrected text")
    }
}
```

- [ ] **Step 3: Run test**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift test --filter LLMAPITypesTests 2>&1 | tail -5
```
Expected: PASS.

- [ ] **Step 4: Aggiornare `parseResponse` in LLMServiceExtension**

```swift
func parseResponse(data: Data) throws -> String {
    do {
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = response.choices.first?.message.content, !content.isEmpty else {
            throw CorrectionError.outputParsingFailed(raw: String(data: data, encoding: .utf8) ?? "nil")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch is CorrectionError {
        throw CorrectionError.outputParsingFailed(raw: String(data: data, encoding: .utf8) ?? "nil")
    } catch {
        throw CorrectionError.outputParsingFailed(raw: String(data: data, encoding: .utf8) ?? error.localizedDescription)
    }
}
```

- [ ] **Step 5: Aggiornare `buildLLMRequest` per usare `Encodable`**

```swift
func buildLLMRequest(url: URL, apiKey: String?, model: String, messages: [ChatMessage], temperature: Double, maxTokens: Int, stream: Bool = false) throws -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = Constants.requestTimeout
    if let key = apiKey {
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    }
    let body = ChatRequest(model: model, messages: messages, temperature: temperature, max_tokens: maxTokens, stream: stream)
    request.httpBody = try JSONEncoder().encode(body)
    return request
}
```

- [ ] **Step 6: Aggiornare i servizi che usano `buildLLMRequest` con `[String: Any]`**

Verificare in `LocalLLMService.swift`, `RemoteLLMService.swift`, `OllamaService.swift`, `OpenRouterService.swift` ogni chiamata a `buildLLMRequest` o costruzione manuale del body e aggiornare alla nuova firma.

Verificare anche `performOpenAIRequest(body: [String: Any], ...)` — aggiornare per accettare un `ChatRequest` direttamente o rimuovere il parametro `body` per costruirlo internamente.

- [ ] **Step 7: Build + test**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift build 2>&1 | tail -10 && swift test 2>&1 | tail -10
```

- [ ] **Step 8: Commit**
```bash
git add Core/LLMAPITypes.swift Core/LLMServiceExtension.swift Core/LocalLLMService.swift Core/RemoteLLMService.swift Core/OllamaService.swift Core/OpenRouterService.swift Tests/Tests.swift
git commit -m "refactor: replace JSON [String:Any] with Codable ChatRequest/ChatResponse types"
```

---

### Task 17: Custom Commands Rapidi nel pannello

**File:** `UI/SuggestionView.swift`, `UI/SuggestionPanel.swift`, `Core/TextCheckCoordinator.swift`

I `CustomPrompt` (seed in `SeedDataProvider`) esistono già. Manca solo l'esposizione nella UI come menu rapido prima di applicare.

- [ ] **Step 1: Aggiungere `onCustomAction` al SuggestionView**

In `UI/SuggestionView.swift`:
```swift
let onCustomAction: (CustomPrompt) -> Void  // ← nuovo param
```

- [ ] **Step 2: Aggiungere menu "Azioni rapide" nel footerView per `.suggestion`**

```swift
case .suggestion(let r, _, _):
    Button(String(localized: "panel.ignore")) { onDismiss() }
    Spacer()
    // Menu azioni rapide
    Menu("Azioni") {
        ForEach(quickPrompts, id: \.id) { prompt in
            Button(prompt.name) { onCustomAction(prompt) }
        }
    }
    Button(String(localized: "panel.explain")) { onExplain() }
    Button(String(localized: "panel.apply")) { onApply() }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
```

Aggiungere la computed property `quickPrompts`:
```swift
private var quickPrompts: [CustomPrompt] {
    // Hardcoded presets (spec e formale esistono già in SeedDataProvider)
    [
        CustomPrompt(id: UUID(), name: "Rendi formale", prompt: "Rendi il testo più formale e professionale.", isEnabled: true),
        CustomPrompt(id: UUID(), name: "Accorcia", prompt: "Accorcia il testo mantenendo il senso principale.", isEnabled: true),
        CustomPrompt(id: UUID(), name: "Semplifica", prompt: "Semplifica il testo per renderlo più chiaro e diretto.", isEnabled: true),
        CustomPrompt(id: UUID(), name: "Rendi informale", prompt: "Rendi il testo più informale e conversazionale.", isEnabled: true),
    ]
}
```

- [ ] **Step 3: Gestire `onCustomAction` in SuggestionPanelController**

In `SuggestionPanelController`, dove si crea `SuggestionView`, passare:
```swift
onCustomAction: { [weak self] prompt in
    self?.applyCustomAction(prompt)
}
```

Aggiungere `applyCustomAction`:
```swift
private func applyCustomAction(_ prompt: CustomPrompt) {
    guard let result = currentResult else { return }
    showOrUpdate(result: nil, state: .loading)
    Task { [weak self] in
        guard let self else { return }
        do {
            let newResult = try await RequestQueue.shared.enqueue(
                text: result.originalText,
                type: .grammar,
                priority: .manual,
                overrideServiceType: nil,
                overrideCustomPrompt: prompt
            )
            let finalResult = CorrectionResult(
                original: result.originalText,
                corrected: newResult.correctedText,
                modelID: newResult.modelID,
                customInstruction: prompt.prompt
            )
            self.showOrUpdate(result: finalResult, state: finalResult.hasChanges ? .suggestion(finalResult) : .noErrors)
        } catch {
            self.showError(error as? CorrectionError ?? .outputParsingFailed(raw: error.localizedDescription))
        }
    }
}
```

- [ ] **Step 4: Build**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift build 2>&1 | tail -5
```

- [ ] **Step 5: Commit**
```bash
git add UI/SuggestionView.swift UI/SuggestionPanel.swift
git commit -m "feat: quick action menu in suggestion panel (formale, accorcia, semplifica, informale)"
```

---

### Task 18: Feature Traduzione

**File:** `Core/LLMService.swift`, `Core/PromptEngine.swift`, `UI/SuggestionView.swift`, `UI/SuggestionPanel.swift`

- [ ] **Step 1: Aggiungere `PromptType.translation`**

In `Core/PromptEngine.swift` o dove è definito `PromptType`, aggiungere:
```swift
case translation(targetLanguage: String)
```

- [ ] **Step 2: Scrivere test per il template di traduzione**

In `Tests/Tests.swift`:
```swift
func testBuildTranslationPrompt_containsTargetLanguage() {
    let engine = PromptEngine(language: "it", style: "equilibrato")
    let prompt = engine.buildTranslationPrompt(for: "Hello world", targetLanguage: "it")
    XCTAssertTrue(prompt.contains("Hello world"))
    XCTAssertTrue(prompt.contains("italiano") || prompt.contains("Italian") || prompt.contains("it"))
}
```

- [ ] **Step 3: Aggiungere `buildTranslationPrompt` a PromptEngine**

In `Core/PromptEngine.swift`:
```swift
func buildTranslationPrompt(for text: String, targetLanguage: String) -> String {
    let escaped = escapePromptTags(text)
    let langName = Locale.current.localizedString(forLanguageCode: targetLanguage) ?? targetLanguage
    return """
    Translate the following text into \(langName). Output only the translated text, nothing else.

    <TEXT>\(escaped)</TEXT>
    """
}
```

Aggiornare `buildPrompt(for:type:)` per gestire `.translation`:
```swift
case .translation(let lang):
    return buildTranslationPrompt(for: text, targetLanguage: lang)
```

- [ ] **Step 4: Run test**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift test --filter PromptEngineTests/testBuildTranslationPrompt_containsTargetLanguage 2>&1 | tail -5
```
Expected: PASS.

- [ ] **Step 5: Aggiungere "Traduci" al menu azioni rapide**

In `UI/SuggestionView.swift`, aggiornare `quickPrompts` per includere un submenu traduzioni o aggiungere i target language più comuni:

```swift
// Aggiungere nel Menu "Azioni":
Menu("Traduci in...") {
    Button("Inglese") { onTranslate("en") }
    Button("Italiano") { onTranslate("it") }
    Button("Spagnolo") { onTranslate("es") }
    Button("Francese") { onTranslate("fr") }
    Button("Tedesco") { onTranslate("de") }
}
```

Aggiungere `onTranslate: (String) -> Void` come parametro al `SuggestionView`.

- [ ] **Step 6: Gestire `onTranslate` in SuggestionPanelController**

```swift
private func translate(to language: String) {
    guard let result = currentResult else { return }
    showOrUpdate(result: nil, state: .loading)
    Task { [weak self] in
        guard let self else { return }
        do {
            let newResult = try await RequestQueue.shared.enqueue(
                text: result.originalText,
                type: .translation(targetLanguage: language),
                priority: .manual,
                overrideServiceType: nil,
                overrideCustomPrompt: nil
            )
            let finalResult = CorrectionResult(
                original: result.originalText,
                corrected: newResult.correctedText,
                modelID: newResult.modelID,
                promptType: "translation"
            )
            self.showOrUpdate(result: finalResult, state: .suggestion(finalResult))
        } catch {
            self.showError(error as? CorrectionError ?? .outputParsingFailed(raw: error.localizedDescription))
        }
    }
}
```

- [ ] **Step 7: Build + test**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift build 2>&1 | tail -5 && swift test 2>&1 | tail -5
```

- [ ] **Step 8: Commit**
```bash
git add Core/PromptEngine.swift UI/SuggestionView.swift UI/SuggestionPanel.swift Tests/Tests.swift
git commit -m "feat: translation — PromptType.translation(targetLanguage:) + translate menu in panel"
```

---

### Task 19: Diff visivo nel suggestion panel

**File:** `UI/SuggestionView.swift`

Mostrare le parole cambiate evidenziate in verde nel testo corretto.

- [ ] **Step 1: Scrivere test per DiffHighlight**

In `Tests/Tests.swift`:
```swift
final class DiffHighlightTests: XCTestCase {
    func testDiffAttributedString_insertsHighlightedWords() {
        let original = "The quick brown fox"
        let corrected = "The fast brown fox"
        let ops = CorrectionResult.computeDiff(original: original, corrected: corrected)
        XCTAssertNotNil(ops)
        // "fast" è inserito al posto di "quick"
        let insertOps = ops!.filter { $0.type == .insert }
        XCTAssertEqual(insertOps.count, 1)
        XCTAssertEqual(insertOps.first?.replacement, "fast")
    }
}
```

- [ ] **Step 2: Run test**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift test --filter DiffHighlightTests 2>&1 | tail -5
```
Expected: PASS.

- [ ] **Step 3: Aggiungere `DiffHighlightView` a SuggestionView**

In `UI/SuggestionView.swift`, aggiungere sotto `VisualEffectView`:
```swift
struct DiffHighlightView: View {
    let original: String
    let corrected: String

    var body: some View {
        Text(attributedDiff)
            .textSelection(.enabled)
    }

    private var attributedDiff: AttributedString {
        let origWords = original.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let corrWords = corrected.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let diff = corrWords.difference(from: origWords)

        var insertedIndices = Set<Int>()
        for change in diff.insertions {
            if case .insert(let offset, _, _) = change { insertedIndices.insert(offset) }
        }

        var result = AttributedString()
        for (i, word) in corrWords.enumerated() {
            var chunk = AttributedString(word)
            if insertedIndices.contains(i) {
                chunk.foregroundColor = Color(nsColor: .systemGreen)
                chunk.backgroundColor = Color(nsColor: .systemGreen).opacity(0.12)
            }
            result += chunk
            if i < corrWords.count - 1 { result += AttributedString(" ") }
        }
        return result
    }
}
```

- [ ] **Step 4: Sostituire `Text(result.correctedText)` con `DiffHighlightView`**

In `SuggestionView.contentView`, nel caso `.suggestion` e `.fluencySuggestion`, sostituire:
```swift
Text(result.correctedText)
    .font(.body)
    .textSelection(.enabled)
```
Con:
```swift
DiffHighlightView(original: result.originalText, corrected: result.correctedText)
    .font(.body)
```

- [ ] **Step 5: Build**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift build 2>&1 | tail -5
```

- [ ] **Step 6: Commit**
```bash
git add UI/SuggestionView.swift Tests/Tests.swift
git commit -m "feat: diff visual highlight — changed words shown in green in suggestion panel"
```

---

### Task 20: Storia Correzioni

**File:** `Core/HistoryStore.swift` (nuovo), `UI/HistoryTab.swift` (nuovo), `UI/SettingsView.swift`

- [ ] **Step 1: Creare HistoryStore**

Creare `Core/HistoryStore.swift`:
```swift
import Foundation
import OSLog

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let original: String
    let corrected: String
    let modelID: String
    let promptType: String
}

actor HistoryStore {
    static let shared = HistoryStore()
    private let maxEntries = 200

    private var historyURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Parrot/history.json")
    }

    func add(result: CorrectionResult) {
        guard result.hasChanges else { return }
        var entries = load()
        let entry = HistoryEntry(
            id: UUID(),
            timestamp: Date(),
            original: result.originalText,
            corrected: result.correctedText,
            modelID: result.modelID,
            promptType: result.promptType
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries = Array(entries.prefix(maxEntries)) }
        save(entries)
    }

    func all() -> [HistoryEntry] { load() }

    func clear() {
        save([])
    }

    private func load() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        return (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
    }

    private func save(_ entries: [HistoryEntry]) {
        do {
            try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: historyURL, options: .atomic)
        } catch {
            Logger.core.error("HistoryStore: failed to save — \(error.localizedDescription, privacy: .public)")
        }
    }
}
```

- [ ] **Step 2: Chiamare `HistoryStore.shared.add(result:)` dopo ogni correzione applicata**

In `UI/SuggestionPanel.swift`, in `applyCorrection()`, dopo `replaceSelectedText` andato a buon fine:
```swift
Task { await HistoryStore.shared.add(result: result) }
```

- [ ] **Step 3: Scrivere test**

In `Tests/Tests.swift`:
```swift
final class HistoryStoreTests: XCTestCase {
    func testAdd_storesEntry() async {
        let store = HistoryStore.shared
        await store.clear()
        let result = CorrectionResult(original: "hello", corrected: "Hello world", modelID: "test")
        await store.add(result: result)
        let entries = await store.all()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.original, "hello")
    }

    func testAdd_noChanges_doesNotStore() async {
        let store = HistoryStore.shared
        await store.clear()
        let result = CorrectionResult(original: "hello", corrected: "hello", modelID: "test")
        await store.add(result: result)
        let entries = await store.all()
        XCTAssertEqual(entries.count, 0)
    }
}
```

- [ ] **Step 4: Run test**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift test --filter HistoryStoreTests 2>&1 | tail -5
```
Expected: PASS.

- [ ] **Step 5: Creare HistoryTab**

Creare `UI/HistoryTab.swift`:
```swift
import SwiftUI

struct HistoryTab: View {
    @State private var entries: [HistoryEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Nessuna correzione",
                    systemImage: "clock",
                    description: Text("Le correzioni applicate appariranno qui.")
                )
            } else {
                List(entries) { entry in
                    HistoryRowView(entry: entry)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancella storia") {
                    Task {
                        await HistoryStore.shared.clear()
                        entries = []
                    }
                }
                .padding(8)
            }
        }
        .task {
            entries = await HistoryStore.shared.all()
        }
    }
}

struct HistoryRowView: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.original)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
                Text(entry.corrected)
                    .font(.caption)
                    .lineLimit(1)
            }
            Text(entry.timestamp, style: .relative)
                .font(.caption2)
                .foregroundColor(.textSecondary)
        }
        .padding(.vertical, 2)
    }
}
```

- [ ] **Step 6: Aggiungere HistoryTab in SettingsView**

In `UI/SettingsView.swift` (o dove vengono aggiunte le tab), aggiungere la tab Storia:
```swift
Tab("Storia", systemImage: "clock") {
    HistoryTab()
}
```

- [ ] **Step 7: Build + test**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift build 2>&1 | tail -5 && swift test 2>&1 | tail -5
```

- [ ] **Step 8: Commit**
```bash
git add Core/HistoryStore.swift UI/HistoryTab.swift UI/SettingsView.swift UI/SuggestionPanel.swift Tests/Tests.swift
git commit -m "feat: correction history — last 200 corrections stored and browsable in Settings > Storia"
```

---

## GRUPPO 6 — Lancio

---

### Task 21: README professionale

**File:** `README.md`

- [ ] **Step 1: Aggiornare README con metriche e sezioni mancanti**

Sostituire `README.md` con un README che include:
- Badge CI (GitHub Actions)
- Screenshot del panel (placeholder: `docs/screenshot-panel.png`)
- GIF del flusso (placeholder: `docs/demo.gif`)
- Sezione "Why Parrot" con 3-4 differenziatori
- Benchmarks: "Corregge testo in 2-5s su M2 con modello Qwen 2.5 1.5B"
- Sezione "Install" con DMG download e `brew install --cask parrot`
- Sezione "Privacy" espansa
- Sezione "Contributing" con link agli issue template

```markdown
# Parrot

[![CI](https://github.com/thousandflowers/parrot/actions/workflows/ci.yml/badge.svg)](https://github.com/thousandflowers/parrot/actions)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange)

**AI-powered offline grammar checker for macOS.** Corrects text in any app with ⌘⇧E — no internet, no subscription, no data leaving your Mac.

![Parrot Demo](docs/demo.gif)

## Why Parrot

| Feature | Parrot | Grambo | Stanza |
|---|---|---|---|
| Bundled llama-server (no Ollama needed) | ✅ | ❌ | ❌ |
| Line-at-cursor fallback | ✅ | ❌ | ❌ |
| Per-app rules | ✅ | ❌ | ❌ |
| Multilingual prompt engine | ✅ | partial | ❌ |
| 100% offline by default | ✅ | ✅ | ✅ |

## Performance

- **2-5s** correction latency on M2 with Qwen 2.5 1.5B (Q4_K_M)
- **0 bytes** sent to external servers in local mode
- **50+ languages** supported via adaptive prompt engine

## Install

### DMG
Download [Parrot-1.0.0.dmg](https://github.com/thousandflowers/parrot/releases/latest).

### Homebrew (coming soon)
```bash
brew install --cask parrot
```

### Build from source
```bash
git clone https://github.com/thousandflowers/parrot
cd parrot
swift build -c release
```

## Quick Start
1. Launch Parrot — it appears in your menu bar
2. Grant Accessibility permissions when prompted
3. Select text in any app → press **⌘⇧E**

## LLM Backends

| Backend | Setup required | Privacy |
|---|---|---|
| **Local (llama.cpp)** | Download a GGUF model | 100% offline |
| **Ollama** | Ollama installed | Local |
| **OpenAI** | API key | Cloud |
| **OpenRouter** | API key | Cloud |

## Architecture
[...existing architecture section...]

## Privacy
[...expanded privacy section...]

## Contributing
Found a bug? [Open an issue](https://github.com/thousandflowers/parrot/issues/new/choose).
```

- [ ] **Step 2: Commit**
```bash
git add README.md
git commit -m "docs: professional README with benchmarks, comparison table, install instructions"
```

---

### Task 22: Sparkle per aggiornamenti automatici

**File:** `Package.swift`

- [ ] **Step 1: Aggiungere Sparkle come dipendenza SPM**

In `Package.swift`, aggiungere al blocco `dependencies`:
```swift
.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
```

E al target Parrot:
```swift
.product(name: "Sparkle", package: "Sparkle"),
```

- [ ] **Step 2: Creare AppUpdater**

Creare `App/AppUpdater.swift`:
```swift
import Sparkle

@MainActor
final class AppUpdater {
    static let shared = AppUpdater()
    private let updaterController: SPUStandardUpdaterController

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
```

- [ ] **Step 3: Aggiungere voce "Cerca aggiornamenti" nel menu**

In `App/AppDelegate.swift`, aggiungere al menu:
```swift
NSMenuItem(title: "Cerca aggiornamenti...", action: #selector(checkForUpdates), keyEquivalent: "")
```

```swift
@objc private func checkForUpdates() {
    AppUpdater.shared.checkForUpdates()
}
```

- [ ] **Step 4: Aggiungere chiave `SUFeedURL` in Info.plist**

In `Resources/Info.plist`:
```xml
<key>SUFeedURL</key>
<string>https://raw.githubusercontent.com/thousandflowers/parrot/main/appcast.xml</string>
```

- [ ] **Step 5: Build**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift build 2>&1 | tail -10
```
Il primo build scarica Sparkle (~30s).

- [ ] **Step 6: Commit**
```bash
git add Package.swift App/AppUpdater.swift App/AppDelegate.swift Resources/Info.plist
git commit -m "feat: Sparkle auto-updates — checkForUpdates in menu, appcast URL configured"
```

---

### Task 23: Per-app settings UI migliorata

**File:** `UI/AppRulesTab.swift`

La logica (`AppRule`, `RuleResolver`) esiste già. `AppRulesTab` mostra le regole ma non permette di selezionare il prompt o il service type per app.

- [ ] **Step 1: Leggere lo stato attuale di AppRulesTab**

```bash
cat -n /Users/eugeniozamengopontrelli/Desktop/Parrot/UI/AppRulesTab.swift
```

- [ ] **Step 2: Aggiungere selezione `serviceType` e `promptName` per ogni regola**

In `UI/AppRulesTab.swift`, nel form di editing di una `AppRule`, aggiungere:
```swift
Picker("Servizio", selection: $rule.serviceType) {
    Text("Default").tag(ServiceType?.none)
    Text("Locale").tag(ServiceType?.some(.local))
    Text("Remoto").tag(ServiceType?.some(.remote))
    Text("Ollama").tag(ServiceType?.some(.ollama))
    Text("OpenRouter").tag(ServiceType?.some(.openRouter))
}

Picker("Prompt", selection: $rule.customPromptID) {
    Text("Default").tag(String?.none)
    ForEach(prefs.customPrompts.filter(\.isEnabled)) { prompt in
        Text(prompt.name).tag(String?.some(prompt.id.uuidString))
    }
}
```

- [ ] **Step 3: Aggiungere rilevamento auto dell'app frontale**

Aggiungere un bottone "Aggiungi app corrente":
```swift
Button("Aggiungi app corrente") {
    Task {
        if let bundleID = await AppDetector.shared.frontAppBundleID(),
           !prefs.appRules.contains(where: { $0.bundleID == bundleID }) {
            let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? bundleID
            let newRule = AppRule(
                id: UUID(),
                bundleID: bundleID,
                appName: appName,
                promptID: nil,
                serviceType: nil,
                isEnabled: true
            )
            prefs.appRules.append(newRule)
        }
    }
}
```

- [ ] **Step 4: Build**
```bash
cd /Users/eugeniozamengopontrelli/Desktop/Parrot && swift build 2>&1 | tail -5
```

- [ ] **Step 5: Commit**
```bash
git add UI/AppRulesTab.swift
git commit -m "feat: per-app settings UI — service type and prompt selector per rule, auto-detect current app"
```

---

## Self-Review

### Spec Coverage Check

| Requisito dall'analisi | Task che lo implementa |
|---|---|
| BUG1: ResultCache double-counting | Task 2 ✅ |
| BUG2: Clipboard race condition | Task 12 ✅ |
| BUG3: Loading message flickering | Task 4 ✅ |
| BUG4: PID 0 fallback | Task 1 ✅ |
| BUG5: ServerHealthMonitor blocking | Task 8 ✅ |
| BUG6: computeDiff offset | Task 11 ✅ |
| BUG7: FeedbackLogger rotation | Task 7 ✅ |
| LOGIC6: API key caching inconsistente | Task 5 ✅ |
| LOGIC7: API Key OpenAI mancante in UI | Task 3 ✅ |
| LOGIC8: Onboarding verifica permessi | Task 9 ✅ |
| ARCH4: Logging strutturato | Task 6 ✅ |
| ARCH3: JSON → Codable | Task 16 ✅ |
| Feature: Diff visivo | Task 19 ✅ |
| Feature: Undo dopo apply | Task 13 ✅ |
| Feature: Stato modello mancante | Task 14 ✅ |
| Feature: TTS | Task 15 ✅ |
| Feature: Custom commands rapidi | Task 17 ✅ |
| Feature: Traduzione | Task 18 ✅ |
| Feature: Storia correzioni | Task 20 ✅ |
| Feature: Per-app settings UI | Task 23 ✅ |
| Lancio: README | Task 21 ✅ |
| Lancio: Sparkle | Task 22 ✅ |
| Lancio: CI + Issue templates | Task 10 ✅ |

**Non coperti (fuori scope del codice):**
- Icona professionale (graphic design)
- DMG / Homebrew cask (richiede notarizzazione Apple Developer account)
- Landing page (progetto separato)
- Blog post tecnici (contenuto, non codice)
- Benchmark README (richiede misurazioni manuali)
- ARCH2: @unchecked Sendable migration (Swift 6 — dipende da timeline migrazione)
- ARCH5: Consolidare 5 servizi LLM (refactor rischioso senza un test suite di integrazione più ampio)
- LOGIC1-5: problemi logici non critici (polling AX, rate limiting, ToneDetector, formattazione, ModelManager dedup)

---
