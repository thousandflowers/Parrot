# RefineClone

AI-powered offline grammar checker for macOS. A privacy-first menubar app that corrects text in any application using local LLM inference via llama.cpp.

## Features

- **Global hotkeys** — `Cmd+Shift+E` checks selected text, `Cmd+Shift+F` opens floating editor
- **Accessibility bridge** — reads/writes text in Mail, Notes, Safari, Chrome, Word, and more
- **Local LLM inference** — runs Qwen 2.5 1.5B / Gemma 4 E2B offline via llama-server
- **BYOK** — optional remote mode with your own OpenAI API key
- **Floating suggestion panel** — shows corrected text near your cursor
- **Explain mode** — click "Explain" to understand why something was corrected
- **Zero data collection** — everything stays on your Mac

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon (M1/M2/M3/M4) or Intel with Metal GPU
- 8+ GB RAM (16 GB recommended for larger models)

## Quick Start

```bash
# 1. Download llama-server
./setup-dev.sh

# 2. Open in Xcode or build with SPM
swift build

# 3. Grant Accessibility permissions
# System Preferences > Privacy & Security > Accessibility > Add RefineClone

# 4. Start llama-server manually (optional — the app auto-starts it)
./llama-server/llama-server \
  -m ~/Library/Application\ Support/RefineClone/Models/qwen2.5-1.5b-instruct-q4_k_m.gguf \
  --port 11434
```

## Architecture

```
RefineClone/
├── App/          — AppDelegate, Constants
├── Core/         — LLMService, PromptEngine, RequestQueue, CorrectionResult
├── Accessibility/— AXUIElement bridge, protocol, mock
├── Shortcuts/    — Carbon global hotkeys
├── UI/           — MenuBar, SuggestionPanel, FloatingEditor, SuggestionView
├── Infra/        — Keychain, ModelManager, Preferences, Server, Cache
└── Resources/    — Info.plist, entitlements
```

## Privacy

- **Offline by default** — local LLM inference, no network required
- **No telemetry** — zero data collection
- **API keys in Keychain** — stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`

## License

MIT
