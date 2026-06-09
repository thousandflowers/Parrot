# Parrot

**⌘⇧E. Grammar fixed. Any app. Offline. Zero bytes sent.**

[![CI](https://github.com/thousandflowers/Parrot/actions/workflows/ci.yml/badge.svg)](https://github.com/thousandflowers/Parrot/actions)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![License: MIT](https://img.shields.io/badge/License-MIT-green)
[![Sponsor](https://img.shields.io/github/sponsors/thousandflowers?label=Sponsor)](https://github.com/sponsors/thousandflowers)

> **Select text → ⌘⇧E → Done.**  
> Correggi grammatica e stile in qualsiasi app macOS — terminale, Xcode, Notion, Figma, Slack — con un modello AI locale. Nessun abbonamento. Nessun cloud.

Sibling: [Wren](https://github.com/thousandflowers/Wren) — inline autocomplete per macOS (stesso codice core, diversa modalità).

---

## Quickstart (10 secondi)

1. **Scarica** [Parrot.dmg](https://github.com/thousandflowers/Parrot/releases/latest) → trascina in Applicazioni
2. **Avvia** → icona ✓ nella menu bar
3. **Concedi** Accessibilità (richiesto al primo avvio)
4. **Scarica un modello** (Impostazioni → Models → `qwen2.5-1.5b`, ~1 GB)
5. **Prova**: apri Note, scrivi *"i writed this yesterday"*, seleziona, premi **⌘⇧E**

```bash
# Homebrew
brew install --cask thousandflowers/parrot/parrot
```

---

## Cosa lo rende diverso

Parrot non è l'ennesimo wrapper di ChatGPT. È un **motore di correzione ibrido** a 4 livelli:

| Strato | Cosa fa | Velocità |
|--------|---------|:--------:|
| ⚡ Regole deterministiche | Errori ovvi (spazi, apostrofi, maiuscole) | istantaneo |
| 🔤 LanguageTool | 500+ regole grammaticali, 25+ lingue, offline | &lt;50ms |
| 📖 Harper | Grammatica inglese avanzata (Rust binary) | &lt;100ms |
| 🤖 LLM locale | Riscritture complesse, fluency, stile | 1-3s |

Ogni strato viene eseguito solo se il precedente non basta. Il LLM locale non viene chiamato per correggere un apostrofo.

Risultato: **correzioni veloci e gratuite per errori semplici**, potenza LLM solo quando serve.

---

## Perché esiste

Scrivere in una seconda lingua è faticoso. Correggere significa: selezionare, copiare, aprire un browser, incollare in un tool, aspettare, copiare il risultato, tornare indietro, incollare.  
Parrot fa tutto in 2 tasti, senza mai uscire dall'app in cui stai scrivendo. Zero contest-switch. Zero cloud. Zero account.

---

## Feature chiave

| Feature | Cosa fa |
|---------|---------|
| **Hybrid correction** | 4 strati (regole → LT → Harper → LLM), chiama il LLM solo quando serve |
| **Span diff** | Accetta o rifiuta correzioni singole, non tutto il blocco. Ogni span mostra fonte (⚡ regola, 🔤 LT, 🤖 LLM) |
| **Per-app rules** | Prompt diverso per ogni app (es. Slack più informale, email più formale) |
| **Custom prompts** | "Scrivi come un pirate" o qualsiasi istruzione tu voglia |
| **Flows** | Catene multi-step: grammatica → semplifica → traduci in francese, con un shortcut |
| **Inline annotations** | Sottolineature in tempo reale mentre scrivi, senza shortcut |
| **StyleProfiler** | Rileva tono e stile da un URL o testo campione, adatta i suggerimenti |
| **Knowledge Base** | Documenti di riferimento iniettati nel prompt LLM per terminologia consistente |
| **Smart Expand** | Trasforma appunti in email complete, legge nomi dai Contatti macOS |
| **Multi-backend** | llama.cpp (incluso), Apple Intelligence, LanguageTool, Harper, Ollama, OpenAI, OpenRouter |
| **Privacy** | Zero KB inviati di default. Tutto su device. Chiavi API in Keychain. Nessun account |

---

## Confronto

| | **Parrot** | Grammarly | LanguageTool | WritingTools | TextWarden |
|---|---|---|---|---|---|
| Funziona in ogni app macOS (terminale, Xcode, Figma…) | ✅ | ❌ | ❌ | ✅ | ✅ |
| Offline, 0 bytes inviati | ✅ | ❌ | parziale | ✅ | ✅ |
| Ibrido regole+LT+Harper+LLM | ✅ | ❌ | ❌ | ❌ | ❌ |
| Span diff (accetta/rifiuta singole) | ✅ | ❌ | ❌ | ❌ | ❌ |
| Per-app rules | ✅ | ❌ | ❌ | ❌ | ❌ |
| Flows multi-step | ✅ | ❌ | ❌ | ❌ | ❌ |
| Knowledge Base personale | ✅ | ❌ | ❌ | ❌ | ❌ |
| Open source | ✅ | ❌ | ✅ | ✅ | ✅ |
| Nessun account/subscription | ✅ | ❌ | ❌ | ✅ | ✅ |

---

## Backend AI

| Backend | Default? | Offline? | Setup |
|---------|:--------:|:--------:|-------|
| **llama.cpp** (incluso) | ✅ default | ✅ | Nessuno — scarica modello da Impostazioni |
| **Apple Intelligence** | auto-fallback su macOS 26 | ✅ | Automatico se llama-server non parte |
| **LanguageTool** (incluso) | parte del layer ibrido | ✅ | Incluso, zero setup |
| **Harper** (incluso) | parte del layer ibrido | ✅ | Incluso, zero setup |
| Ollama | ❌ | ✅ | `brew install ollama` |
| OpenAI / OpenRouter | ❌ | ❌ | Inserisci API key |

---

## Stato

**Release corrente**: [0.9.3](https://github.com/thousandflowers/Parrot/releases)

| Feature | Stato |
|---------|:-----:|
| Grammar / Fluency / Translate / Coach / De-Slop | ✅ |
| Span-based diff panel | ✅ |
| Hybrid engine (rules + LT + Harper + LLM) | ✅ |
| Inline annotations | ✅ |
| StyleProfiler + offline learning | ✅ |
| Smart Expand + Contacts | ✅ |
| Knowledge Base | ✅ |
| Flows, Story Analyzer | ✅ |
| Per-app rules, Custom rules (regex) | ✅ |
| Export / Import configurazione | ✅ |
| Apple Intelligence backend (macOS 26) | ✅ |
| iCloud sync | ✅ |
| Homebrew cask | ✅ |
| Notarized build | ◻︎ in progress |
| Mac App Store | ◻︎ planned |

---

## Build

```bash
git clone https://github.com/thousandflowers/Parrot
cd Parrot
swift build -c release
./build-app.sh release
```

Requisiti: macOS 14+, Xcode 16 / Swift 5.10.

---

## Architettura

Swift/SwiftUI. Stato condiviso via `actor` (zero data race). LLM in subprocesso isolato (nessun impatto UI). Testo letto/scritto via API `AXUIElement`.

Vedi [docs/architecture.md](docs/architecture.md) per dettagli.

---

## License

MIT — [LICENSE](LICENSE).
