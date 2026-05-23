# Parrot

[![CI](https://github.com/thousandflowers/Parrot/actions/workflows/ci.yml/badge.svg)](https://github.com/thousandflowers/Parrot/actions)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square)
![License: MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/thousandflowers?style=flat-square&label=Sponsor)](https://github.com/sponsors/thousandflowers)

**Select text. Press ⌘⇧E. Done.**

Parrot is a macOS menu bar app that corrects your writing in any app — terminal, Xcode, Notion, Figma, anywhere — using a local AI model that never sends your text anywhere. No subscription. No browser extension. No cloud. Just a keyboard shortcut and a floating panel that shows you exactly what changed.

> Works on macOS 14 Sonoma and macOS 26 Tahoe.

---

<!-- Replace this line with a GIF or screen recording of the full flow -->
![Demo](docs/demo.gif)

---

## In 10 seconds

- **Press ⌘⇧E** in any app — Parrot reads the selected text via the macOS Accessibility API, corrects it, and shows a diff panel next to your cursor
- **One more keypress** applies the correction back into the focused field — no copy-paste, no context switch
- **The AI runs locally** by default (a bundled `llama-server`). On macOS 26 you can use Apple Intelligence instead. Zero bytes leave your Mac either way
- **No daemon, no extension, no account.** Install once, grant Accessibility permission, pick a model, start writing

---

## Why I built Parrot

I write a lot in my second language. I have dyslexia. Every time I wanted to fix a sentence in Xcode, in a terminal commit message, or in a chat window, I had to copy the text, open a browser tab, paste it into some tool that either required an account or sent my words to a server in another country, then copy the result back.

I wanted something that would just sit in the menu bar, work everywhere without exceptions, run offline, and disappear the moment I pressed Enter. Nothing I found did all of that. So I built it.

---

## Who is this for?

**Students and non-native writers** — you write theses, essays, and emails in a language that's not your first. You want immediate feedback, privately, without switching app or losing your train of thought.

**Developers** — you write code comments, commit messages, PR descriptions, and Slack messages all day long. Grammarly doesn't work in your terminal or IDE. Parrot does.

**Writers** — you draft in any editor, from iA Writer to VS Code to plain TextEdit. You want a grammar pass with a diff view that shows exactly what changed, not a full rewrite.

**Professionals** — you send a lot of email and Slack messages. You want a fast sanity check before you hit Send, without your words going through someone else's servers.

---

## Get started in 1 minute

1. **Download** [Parrot.dmg](https://github.com/thousandflowers/Parrot/releases/latest) and drag the app to `/Applications`
2. **Launch Parrot** — a small ✓ icon appears in your menu bar
3. **Grant Accessibility access** when prompted *(System Settings → Privacy & Security → Accessibility → add Parrot)*
4. **Download a model** — open Settings → Models → download `qwen2.5-1.5b` (~1 GB, fast on M1+). Or enter an OpenAI/OpenRouter API key if you prefer cloud
5. **Try it** — open Notes, type *"i writed this yesterday"*, select it, press **⌘⇧E**. The correction panel appears in under 3 seconds

> **First launch on macOS:** if you see "unidentified developer", right-click the app → Open. A notarized build is on the roadmap.

Or install via Homebrew:
```bash
brew install --cask thousandflowers/parrot/parrot
```

---

## How it works

```
Select text in any app
       ↓
  ⌘⇧E (or your custom shortcut)
       ↓
Parrot reads selected text via AXUIElement API
       ↓
Local LLM (llama-server) corrects it — 0 bytes leave your Mac
       ↓
Floating diff panel appears next to your cursor
       ↓
  Return — correction is written back into the focused field
```

Parrot uses the macOS Accessibility API to read and write text directly in the focused UI element. It does not touch the system clipboard. If the Accessibility API is not available for a specific app, it falls back to clipboard injection automatically.

---

## Parrot vs. Grammarly vs. LanguageTool

|  | **Parrot** | Grammarly | LanguageTool |
|---|---|---|---|
| Works in every macOS app (terminal, Xcode, Figma…) | ✅ | ❌ | ❌ |
| Offline by default, 0 bytes sent | ✅ | ❌ | partial |
| No account, no subscription, no extension | ✅ | ❌ | partial |
| Per-app rules (different prompt for each app) | ✅ | ❌ | ❌ |
| Open source | ✅ | ❌ | ✅ |

---

## Features

**Correction modes** — Grammar, Fluency, Translate, Writing coach, and fully custom prompts. Bind any mode to a shortcut.

**Diff panel** — See exactly which words changed, highlighted in green. Toggle to a clean result view. One-click apply, explain, translate, or undo.

**Flows** — Chain multiple steps into a single action: *grammar → simplify → translate to French*. Save flows and trigger them with a shortcut.

**Floating Editor** — A full split-screen editor for longer texts. Includes dictation input, file import, and a **Story Analyzer** that scores narrative structure, pacing, and style for manuscripts over 100 words.

**Intelligence** — Language auto-detection (50+ languages), per-app rules, real-time mode (auto-checks as you pause typing), correction history, ignore list. Grammar mode targets minimum changes and preserves verb tense, mood, gender, and voice — corrections are surgical, not rewrites. Article and determiner allomorphy (Italian *un/uno/il/lo/i/gli*, French contractions, English *a/an*) handled correctly across all supported languages.

**Privacy and sync** — iCloud sync for settings and history across your Macs. Local-only mode keeps everything on device. API keys stored in Keychain, never on disk.

**Backends** — llama.cpp (bundled, default), Apple Intelligence (macOS 26+, no download needed), Ollama, OpenAI, OpenRouter.

---

## Status

**Current release: 0.9.2**

| Feature | Status |
|---|---|
| Grammar / Fluency / Translate correction | ✔ shipped |
| Offline local LLM (llama-server bundled) | ✔ shipped |
| Apple Intelligence backend (macOS 26) | ✔ shipped |
| Flows, Story Analyzer, Knowledge Base | ✔ shipped |
| iCloud sync | ✔ shipped |
| Homebrew cask | ✔ shipped |
| Notarized release (no right-click needed) | ◻︎ in progress |
| Mac App Store | ◻︎ planned |

### What's new in 0.9.2

- **Grammar quality** — fixed obvious syntax errors being missed due to over-aggressive validation guards; error-heavy sentences now correct fully
- **Article allomorphy** — *un/uno*, *il/lo*, *i/gli* (IT), *a/an* (EN), *de le/du* (FR) handled correctly without hard-coded rules
- **No tense/mood/gender changes** — grammar mode now preserves verb tense, subjunctive, conditional, and grammatical gender exactly
- **WhatsApp and Electron apps** — text replacement now works in WhatsApp, Slack, Discord, VS Code, Notion, and all other Electron-based apps
- **macOS 26 stability** — fixed constraint-loop crash (`NSHostingView` re-entrancy) on macOS Tahoe

---

## Architecture

Swift/SwiftUI app using `actor` for all shared state (zero data races by construction). The AI inference runs via a bundled `llama-server` subprocess — no Ollama dependency, no always-on daemon, no port conflicts. Text is read and written via `AXUIElement` APIs directly into the focused UI element.

See [docs/architecture.md](docs/architecture.md) for a full breakdown of the module structure, the macOS 26 constraint-loop fix, and design decisions.

---

## Build from source

```bash
git clone https://github.com/thousandflowers/Parrot
cd Parrot
swift build -c release
./build-app.sh release   # produces Parrot.app + Parrot.dmg
```

**Requirements:** macOS 14+, Xcode 16 / Swift 5.10.

---

## Contributing

Bug report → [open an issue](https://github.com/thousandflowers/Parrot/issues/new?template=bug_report.md)
Feature idea → [open a discussion](https://github.com/thousandflowers/Parrot/discussions)
Easy first tasks → [good first issue](https://github.com/thousandflowers/Parrot/labels/good%20first%20issue)

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## License

MIT — see [LICENSE](LICENSE).
