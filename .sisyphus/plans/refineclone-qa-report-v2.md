# RefineClone — Report QA Completo v2

> **Data**: 13 Maggio 2026  
> **Build**: Release (SwiftPM 5.10)  
> **Metodo**: AppleScript System Events + coordinate click + screenshot  
> **Stabilità**: ✅ **Zero crash** in oltre 20 minuti di test intensivo  

---

## 🔴 CRITICAL

### 1. Modelli off-screen — NON completamente risolto
**File**: `UI/SettingsView.swift` → ModelsTab  
**Evidenza**: Screenshot `/tmp/refineclone_modelli_final.png`, `/tmp/refineclone_modelli_scrolled.png`

L'HStack duplicato è stato rimosso (fix T1 precedente), ma **Phi-3.5 Mini** e **Gemma 4 E2B IT** sono ancora invisibili. Solo 6 modelli su 8+ sono visibili. Lo scroll (Page Down) non mostra i modelli nascosti. **La scrollbar stessa non è visibile**.

Il `List` con `.listStyle(.inset)` e il `VStack` esterno potrebbero non calcolare correttamente l'altezza del contenuto. Root cause: la `List` in un `VStack` all'interno di un `TabView` su macOS non espande automaticamente.

**Fix suggerito**: Sostituire `List` con `ScrollView { LazyVStack { ... } }` oppure aggiungere `.frame(minHeight: 400)` alla List.

---

## 🟠 HIGH

### 2. StubLLMService non distingue Grammar vs Fluency
**File**: `Core/StubLLMService.swift`  
**Evidenza**: Screenshot `/tmp/refineclone_fluency.png`

In modalità Fluidità, lo Stub restituisce `[CORRETTO-STUB: Errori grammaticali corretti]` — lo stesso output della modalità Grammatica. Il servizio non differenzia i due tipi di check.

**Impatto**: Test e demo della funzionalità fluidità sono impossibili con Stub.

**Fix**: Modificare `StubLLMService` per restituire output diverso in base al `CheckType`.

### 3. MenuBar dropdown inaccessibile via AX
**File**: `RefineCloneApp.swift`, `UI/MenuBarView.swift`  
**Evidenza**: `find_elements_in_app("RefineClone")` ritorna vuoto; `SystemUIServer` non espone gli elementi del MenuBarExtra.

Nonostante i fix T2 (`.accessibilityLabel()` su tutti i bottoni), il dropdown rimane inaccessibile agli strumenti AX perché il MenuBarExtra è figlio di SystemUIServer, non del processo RefineClone.

**Impatto**: VoiceOver non può accedere all'interfaccia primaria. Automation impossibile.

---

## 🟡 MEDIUM

### 4. Copia button copia testo originale con Stub
**File**: `UI/FloatingEditor.swift`  
**Evidenza**: Dopo check, `pbpaste` restituisce 155 caratteri (solo testo originale, senza correzione Stub).

Lo `StubLLMService` restituisce il testo originale invariato come `correctedText`. La nota `[CORRETTO-STUB: ...]` è solo display. Il pulsante "Copia" copia `correctedText` che per lo Stub è identico all'originale.

**Impatto**: Funzionalità Copia inutile in modalità Stub.

### 5. HF Token field non accetta paste
**File**: `UI/SettingsView.swift` → AdvancedTab  
**Evidenza**: Screenshot `/tmp/refineclone_hf_token.png` mostra campo vuoto dopo paste.

Il `SecureField` SwiftUI potrebbe non accettare il paste via `keystroke "v" using command down` di AppleScript. Il pulsante "Salva" rimane disabilitato.

**Nota**: Potrebbe essere un problema solo dell'automazione AppleScript, non un bug reale.

### 6. Checkbox "Controllo in tempo reale" rimane unchecked
**File**: `UI/SettingsView.swift` → GeneralTab  
**Evidenza**: Screenshot `/tmp/refineclone_generale_toggles.png` mostra checkbox unchecked.

Anche con "Controllo automatico" checked, la checkbox "tempo reale" è unchecked. Due click la riportano a unchecked (toggle 0→1→0 funziona). Lo stato iniziale è unchecked, che è il comportamento di default.

---

## 🟢 LOW

### 7. UX: nessun feedback quando il check fallisce
**File**: `UI/FloatingEditor.swift`  
**Evidenza**: Fix T7 implementato (pulsanti "Riprova" e "Usa Stub") ma non visibili perché il check Stub non fallisce mai.

Per verificare i pulsanti T7 bisognerebbe switchare a servizio "Locale" senza server attivo. Non testabile in questa sessione.

---

## ✅ COSA FUNZIONA (VERIFICATO)

| Funzionalità | Stato | Note |
|---|---|---|
| Avvio app | ✅ | Nessun crash, PID stabile |
| Settings via CMD+, | ✅ | Finestra "Generale" aperta |
| **Correzione Grammatica (Stub)** | ✅ | Testo nel pannello "Corretto" con output `[CORRETTO-STUB]` |
| **Correzione Fluidità (Stub)** | ✅ | Check eseguito, output nel pannello destro |
| Pulsante "Copia" | ✅ | Abilitato dopo check, copia negli appunti |
| Tab Prompt | ✅ | 3 template visibili |
| Tab Regole App | ✅ | Vuoto (corretto) |
| Tab Esclusioni | ✅ | 4 esclusioni preconfigurate |
| Tab Avanzate | ✅ | Token HF, stato accessibilità, bundle |
| Servizio picker | ✅ | Mostra "Stub (test)" |
| Checkbox toggle | ✅ | Rispondono ai click |
| HStack duplicato (T1) | ✅ | Rimosso, header "Server fermo" singolo |
| Alert accessibilità (T6) | ✅ | Non mostrato dopo flag `hasAcknowledgedAccessibilityWarning` |
| Stabilità generale | ✅ | Zero crash in 20+ minuti |

---

## 📊 RIEPILOGO BUG

| # | Bug | Gravità | Stato |
|---|-----|---------|-------|
| 1 | Modelli off-screen (Phi-3.5, Gemma 4 E2B) | 🔴 Critical | **ANCORA APERTO** |
| 2 | Stub non differenzia grammar/fluency | 🟠 High | **NUOVO** |
| 3 | MenuBar AX inaccessibile | 🟠 High | **ANCORA APERTO** |
| 4 | Copia con Stub copia originale | 🟡 Medium | **NUOVO** |
| 5 | HF Token paste non funziona | 🟡 Medium | Da verificare manualmente |
| 6 | Checkbox tempo reale default unchecked | 🟡 Medium | Comportamento atteso? |
| 7 | Pulsanti errore T7 non testabili | 🟢 Low | Richiede server locale |

---

## 🎯 TEST GRAMMAR/FLUENCY — FUNZIONA?

**SÌ** — La correzione grammatica e fluidità **funziona** con il servizio Stub:
- Testo inserito nell'Editor (29 parole) ✅
- Click "Controlla" → output prodotto nel pannello "Corretto" ✅
- Modalità "Fluidità" → check eseguito ✅
- Pulsante "Copia" abilitato dopo check ✅

**MA** lo Stub non distingue tra grammar e fluency. Per test reali serve un server LLM attivo (Ollama/llama.cpp).
