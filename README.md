# Parrot

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square)
![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange?style=flat-square)
![License: MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square)
![Tests](https://img.shields.io/badge/tests-92%20passing-brightgreen?style=flat-square)

**Grammar and style correction for every app on your Mac — offline, instant, no subscription.**

Parrot lives in your menu bar. Select text anywhere, press **⌘⇧E**, and the corrected version appears in a floating panel. One more keypress applies it. No cloud required.

---

## How it works

```
Select text in any app  →  ⌘⇧E  →  Review panel  →  Return to apply
```

Parrot uses the macOS Accessibility API to read and write text directly in the focused element — no clipboard hijacking, no context switching. The LLM runs locally on your machine by default (via a bundled `llama-server` binary), so the text never leaves your Mac.

---

## Features

### Correction modes
| Shortcut | Mode | What it does |
|---|---|---|
| `⌘⇧E` | Grammar | Fixes spelling, grammar, punctuation |
| `⌘⇧T` | Fluency | Rewrites for clarity without changing meaning |
| `⌘⇧U` | Translate | Translates to EN / IT / ES / FR / DE |
| `⌘⇧W` | Writing coach | Suggests structural improvements |
| Custom | Presets | "Make formal", "Shorten", "Simplify" — one click |

### Panel
- **Diff highlight** — changed words shown in green, so you see exactly what changed
- **Explain** — ask the model to justify each correction inline
- **Text-to-speech** — hear the corrected version before applying
- **Undo** — 5-second revert window after applying
- **Apply all** — accept every suggestion at once

### Intelligence
- **Language auto-detection** — adapts the prompt to the text's language automatically (50+ languages)
- **Per-app rules** — set a different model, tone, or prompt for each application
- **Real-time mode** — auto-checks when you pause typing (optional, off by default)
- **Correction history** — browse and re-apply past corrections in Settings
- **Custom prompts** — write your own reusable templates with hotkey bindings

### Privacy
- Local LLM inference by default — **zero bytes sent to external servers**
- No telemetry, no analytics, no crash reporting
- API keys stored in macOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), never on disk
- Optional feedback log stored locally at `~/Library/Application Support/Parrot/feedback.jsonl`, never uploaded

---

## LLM backends

| Backend | What you need | Data stays |
|---|---|---|
| **Local (llama.cpp)** | Download a GGUF model in Settings | On your Mac |
| **Ollama** | Ollama installed + model pulled | On your Mac |
| **OpenAI** | API key | OpenAI servers |
| **OpenRouter** | API key | Provider servers |

**Recommended model:** `qwen2.5-1.5b-instruct-q4_k_m.gguf` (~1 GB) — fast enough for real-time use on M-series chips.

---

## Why not Grammarly / LanguageTool?

| | Parrot | Grammarly | LanguageTool |
|---|---|---|---|
| Works in every app (terminal, Xcode, Figma…) | ✅ | ❌ | ❌ |
| Fully offline | ✅ | ❌ | partial |
| Bundled inference (no Ollama, no server) | ✅ | — | — |
| Per-app rules | ✅ | ❌ | ❌ |
| Custom prompts | ✅ | ❌ | ❌ |
| No subscription | ✅ | ❌ | partial |
| Open source | ✅ | ❌ | ✅ |

---

## Install

### Download
Download the latest DMG from the [Releases](https://github.com/thousandflowers/Parrot/releases/latest) page.

### Build from source

**Requirements:** macOS 14+, Xcode 16+ or Swift 5.10 toolchain.

```bash
git clone https://github.com/thousandflowers/Parrot
cd Parrot
swift build -c release --arch arm64
```

To build a signed `.app` bundle:

```bash
# Unsigned (local use)
./build-app.sh release

# Signed + notarized (distribution)
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARIZE_TEAM_ID="TEAMID" \
NOTARIZE_APPLE_ID="you@example.com" \
NOTARIZE_PASSWORD="@keychain:altool" \
./build-app.sh release
```

### Run tests

```bash
swift test
```

---

## Quick start

1. Launch Parrot — a **✓** icon appears in your menu bar
2. Grant **Accessibility** permission when prompted *(System Settings → Privacy & Security → Accessibility)*
3. In Settings, download a model or paste an API key
4. Select text anywhere → press **⌘⇧E**
5. Review the suggestion → press **Return** to apply or **Esc** to dismiss

---

## Architecture

```
Parrot/
├── App/           AppDelegate, Constants, AppUpdater (Sparkle)
├── Core/          LLMService, PromptEngine, RequestQueue, CorrectionResult, HistoryStore
├── Accessibility/ AXUIElement bridge, AppDetector, clipboard fallback
├── Shortcuts/     Carbon global hotkey registration
├── UI/            MenuBarView, SuggestionPanel, FloatingEditor, SettingsView tabs
├── Infra/         Keychain, ModelManager, ServerManager (llama-server), ResultCache
└── Resources/     Info.plist, entitlements, localizations (7 languages)
```

**Design decisions:**
- Swift `actor` for every piece of shared mutable state — zero data races by construction
- `llama-server` spawned as a managed subprocess — no Ollama dependency, no daemon, no port conflicts
- `AXUIElement` API writes text directly into the focused element; clipboard injection is the fallback for apps that block AX writes
- `PromptEngine` detects the text's language via `NLLanguageRecognizer` and selects the appropriate system prompt and grammar rules automatically

---

## Requirements

- macOS 14.0 Sonoma or later
- Apple Silicon (M1 or newer) recommended; Intel + Metal GPU supported
- 4 GB RAM minimum; 16 GB recommended for 3B+ parameter models
- Accessibility permission

---

## Contributing

Bug reports and pull requests are welcome.

- **Bug:** [open a bug report](https://github.com/thousandflowers/Parrot/issues/new?template=bug_report.md)
- **Feature:** open an issue before sending a PR for non-trivial changes

```bash
# Development build
swift build

# Run a specific test
swift test --filter PromptEngineTests
```

---

## License

MIT — see [LICENSE](LICENSE).
