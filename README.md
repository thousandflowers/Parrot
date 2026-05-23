# Parrot

[![CI](https://github.com/thousandflowers/Parrot/actions/workflows/ci.yml/badge.svg)](https://github.com/thousandflowers/Parrot/actions)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square)
![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange?style=flat-square)
![License: MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square)
![Tests](https://img.shields.io/badge/tests-92%20passing-brightgreen?style=flat-square)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/thousandflowers?style=flat-square&label=Support)](https://github.com/sponsors/thousandflowers)

**Grammar and style correction for every app on your Mac — offline, instant, no subscription.**

🌐 **[parrot.sh](https://parrot.sh)** — Parrot lives in your menu bar. Select text anywhere, press **⌘⇧E**, and the corrected version appears in a floating panel next to your cursor. One keypress applies it. Nothing leaves your Mac.

---

## Screenshots

| Suggestion panel | Menu bar |
|---|---|
| ![Panel](docs/screenshot-panel.png) | ![Menu](docs/screenshot-menu.png) |

_The panel shows a diff of what changed (green = corrected words), with one-click apply, explain, and TTS._

---

## Who is this for?

- **Students and academics** — writing a thesis or report in Italian, English, or any other language? Parrot corrects grammar and improves fluency without switching app or losing focus.
- **Professionals** — fix tone and grammar in emails, Slack messages, Notion docs before you hit Send.
- **Developers** — clean up code comments, commit messages, and docs directly in Xcode, VSCode, or the terminal.
- **Writers** — polish tweets, Substack posts, or newsletter drafts in any editor, with one shortcut.
- **Non-native speakers** — get instant feedback on phrasing in your second language, with full offline privacy.

---

## How it works

```
Select text in any app  →  ⌘⇧E  →  Review panel  →  Return to apply
```

Parrot uses the macOS Accessibility API to read and write text directly in the focused element — no clipboard hijacking, no context switch. The LLM runs locally by default (bundled `llama-server`), so text never leaves your Mac.

---

## Performance & privacy

| | Local (llama.cpp) | Ollama | OpenAI / OpenRouter |
|---|---|---|---|
| Avg. latency on M2 | ~3s (1.5B model) | ~3–5s | ~1–2s |
| Data sent externally | **0 bytes** | **0 bytes** | Text sent to provider |
| Internet required | No | No | Yes |
| Setup | Download model in Settings | Ollama + model installed | API key in Settings |

> In local mode, **nothing leaves your Mac** — no text, no metadata, no analytics. With OpenAI or OpenRouter, your text passes through their servers according to their privacy policies.

Recommended model for everyday use: `qwen2.5-1.5b-instruct-q4_k_m.gguf` (~1 GB, fast enough for real-time mode on M1+).

---

## Install

### For most people — download the app

1. Download **[Parrot.dmg](https://github.com/thousandflowers/Parrot/releases/latest)** from the Releases page
2. Open the DMG, drag Parrot to `/Applications`
3. Launch Parrot — a **✓** appears in your menu bar
4. Grant **Accessibility** permission when prompted *(System Settings → Privacy & Security → Accessibility)*
5. In Settings, download a model or enter an API key

> First launch: macOS may warn "unidentified developer". Right-click the app → **Open** to bypass Gatekeeper (ad-hoc signed build). A notarized release is planned.

### Build from source

**Requirements:** macOS 14+, Swift 5.10 toolchain (Xcode 16+).

```bash
git clone https://github.com/thousandflowers/Parrot
cd Parrot
swift build -c release --arch arm64
```

To produce a signed `.app` + DMG:

```bash
# Unsigned — for local testing
./build-app.sh release

# Signed + notarized — for distribution
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARIZE_TEAM_ID="TEAMID" \
NOTARIZE_APPLE_ID="you@example.com" \
NOTARIZE_PASSWORD="@keychain:altool" \
./build-app.sh release
```

---

## Features

### Correction modes

| Shortcut | Mode | What it does |
|---|---|---|
| `⌘⇧E` | Grammar | Fixes spelling, grammar, punctuation |
| `⌘⇧T` | Fluency | Rewrites for clarity without changing meaning |
| `⌘⇧Y` | Translate | Translates to your target language |
| `⌘⇧W` | Writing coach | Suggests structural improvements |
| Custom | Presets | "Make formal", "Shorten", "Simplify" — one click |

### Panel
- **Diff highlight** — changed words shown in green so you see exactly what changed
- **Explain** — ask the model to justify each correction inline
- **Text-to-speech** — hear the corrected version before applying
- **Undo** — 5-second revert window after applying
- **Apply all** — accept every suggestion at once

### Intelligence
- **Language auto-detection** — adapts the prompt to the text's language automatically (50+ languages)
- **Per-app rules** — different model, tone, or prompt for each application
- **Real-time mode** — auto-checks when you pause typing (optional, off by default)
- **Correction history** — browse and re-apply past corrections in Settings
- **Custom prompts** — reusable templates with hotkey bindings

---

## Why not Grammarly / LanguageTool?

| | Parrot | Grammarly | LanguageTool |
|---|---|---|---|
| Works in every app (terminal, Xcode, Figma…) | ✅ | ❌ | ❌ |
| Fully offline by default | ✅ | ❌ | partial |
| No daemon, no browser extension | ✅ | ❌ | ❌ |
| Per-app rules | ✅ | ❌ | ❌ |
| Custom prompts | ✅ | ❌ | ❌ |
| No subscription | ✅ | ❌ | partial |
| Open source | ✅ | ❌ | ✅ |

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
- `AXUIElement` API writes text directly into the focused element; clipboard injection is the fallback
- `PromptEngine` detects the text's language via `NLLanguageRecognizer` and selects the appropriate system prompt automatically

---

## Roadmap

- [ ] Notarized release (proper Gatekeeper pass, no right-click needed)
- [x] PopClip extension (select text in PopClip → correct with one tap)
- [ ] Native TTS voices per language
- [ ] iCloud sync for custom rules and history
- [ ] Homebrew cask (`brew install --cask parrot`) — pending notarized release
- [ ] Landing page at parrot.sh

---

## Requirements

- macOS 14.0 Sonoma or later
- Apple Silicon (M1 or newer) recommended; Intel + Metal GPU supported
- 4 GB RAM minimum; 16 GB recommended for 3B+ parameter models
- Accessibility permission (Privacy & Security → Accessibility)

---

## Privacy

- **Offline by default** — local LLM inference, zero network requests
- **No telemetry** — no analytics, no crash reporting, no data collection of any kind
- **API keys in Keychain** — stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, never written to disk
- **Feedback log** — optional, local only: `~/Library/Application Support/Parrot/feedback.jsonl`, text truncated to 500 chars, never uploaded
- **Correction history** — stored locally at `~/Library/Application Support/Parrot/history.json`, never leaves your Mac

---

## Contributing

Found a bug? [Open a bug report](https://github.com/thousandflowers/Parrot/issues/new?template=bug_report.md).
Have an idea? [Open a feature request](https://github.com/thousandflowers/Parrot/issues/new?template=feature_request.md).
Looking for something easy to start with? Check [good first issues](https://github.com/thousandflowers/Parrot/labels/good%20first%20issue).

Pull requests welcome. Please open an issue first for non-trivial changes.

```bash
swift test                              # run all 92 tests
swift test --filter PromptEngineTests   # run a specific suite
swift build                             # debug build
```

---

## License

MIT — see [LICENSE](LICENSE).
