# RefineClone

[![CI](https://github.com/thousandflowers/refineclone/actions/workflows/ci.yml/badge.svg)](https://github.com/thousandflowers/refineclone/actions)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

**AI-powered offline grammar checker for macOS.** Corrects text in any app with ⌘⇧E — no internet, no subscription, no data leaving your Mac.

![RefineClone Demo](docs/demo.gif)

## Why RefineClone

| Feature | RefineClone | Grammarly | LanguageTool |
|---|---|---|---|
| Bundled llama-server (no Ollama needed) | ✅ | ❌ | ❌ |
| Line-at-cursor fallback | ✅ | ❌ | ❌ |
| Per-app rules | ✅ | ❌ | ❌ |
| Multilingual prompt engine | ✅ | partial | ✅ |
| 100% offline by default | ✅ | ❌ | partial |
| No subscription | ✅ | ❌ | partial |
| Open source | ✅ | ❌ | ✅ |

## Performance

- **2-5s** correction latency on M2 with Qwen 2.5 1.5B (Q4_K_M)
- **0 bytes** sent to external servers in local mode
- **50+ languages** supported via adaptive prompt engine

## Install

### DMG
Download [RefineClone-1.0.0.dmg](https://github.com/thousandflowers/refineclone/releases/latest).

### Homebrew (coming soon)
```bash
brew install --cask refineclone
```

### Build from source
```bash
git clone https://github.com/thousandflowers/refineclone
cd refineclone
swift build -c release
```

## Quick Start

1. Launch RefineClone — it appears in your menu bar as ✓
2. Grant Accessibility permissions when prompted (required to read/write text in other apps)
3. Select text in any app → press **⌘⇧E**
4. Review the suggestion in the floating panel → press **Return** to apply or **Esc** to dismiss

## Features

- **Grammar check** — `⌘⇧E`: corrects spelling, grammar, punctuation
- **Fluency check** — `⌘⇧T`: rewrites for clarity and flow without changing meaning
- **Floating suggestion panel** — appears near your cursor, auto-dismisses on apply
- **Diff highlight** — changed words shown in green
- **Explain mode** — "Spiega" button asks the model to justify each correction
- **Text-to-speech** — listen to the corrected version before applying
- **Undo** — 5-second window to revert after applying
- **Translation** — translate corrected text to EN/IT/ES/FR/DE
- **Quick actions** — "Rendi formale", "Accorcia", "Semplifica" in one click
- **Correction history** — browse and re-apply past corrections in Settings
- **Per-app rules** — use different models or prompts per application
- **Real-time monitor** — auto-checks when you pause typing (optional)

## LLM Backends

| Backend | Setup | Privacy |
|---|---|---|
| **Local (llama.cpp)** | Download a GGUF model in Settings | 100% offline |
| **Ollama** | Ollama installed + model pulled | Local |
| **OpenAI** | API key in Settings | Cloud |
| **OpenRouter** | API key in Settings | Cloud |

Recommended model: `qwen2.5-1.5b-instruct-q4_k_m.gguf` (~1 GB, M-series optimized).

## Architecture

```
RefineClone/
├── App/          — AppDelegate, Constants, AppUpdater
├── Core/         — LLMService, PromptEngine, RequestQueue, CorrectionResult, HistoryStore
├── Accessibility/— AXUIElement bridge, AppDetector
├── Shortcuts/    — Carbon global hotkeys
├── UI/           — MenuBarView, SuggestionPanel, FloatingEditor, SettingsView, HistoryTab
├── Infra/        — Keychain, ModelManager, PreferencesStore, ServerManager, ResultCache
└── Resources/    — Info.plist, entitlements
```

Key design decisions:
- **Swift actors** for all shared mutable state (zero data races)
- **llama-server** spawned as subprocess — no Ollama dependency for local inference
- **AXUIElement** reads/writes text directly in the focused element; clipboard injection as fallback
- **PromptEngine** detects language and adapts system prompt automatically

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon (M1–M4) recommended; Intel with Metal GPU supported
- 8+ GB RAM (16 GB recommended for 3B+ models)
- Accessibility permission (Privacy & Security → Accessibility)

## Privacy

- **Offline by default** — local LLM inference, no network requests in local mode
- **No telemetry** — zero analytics, zero data collection, no crash reporting
- **API keys in Keychain** — stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; never written to disk in plaintext
- **Feedback log** — optional local file at `~/Library/Application Support/RefineClone/feedback.jsonl`; text truncated to 500 chars; never uploaded
- **Correction history** — stored locally at `~/Library/Application Support/RefineClone/history.json`; never leaves your Mac

## Contributing

Found a bug? [Open a bug report](https://github.com/thousandflowers/refineclone/issues/new?template=bug_report.md).

Have a feature idea? [Open a feature request](https://github.com/thousandflowers/refineclone/issues/new?template=feature_request.md).

Pull requests welcome. Please open an issue first for non-trivial changes.

```bash
# Run tests
swift test

# Build release
swift build -c release
```

## License

MIT — see [LICENSE](LICENSE).
