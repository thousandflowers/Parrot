# Parrot

[![CI](https://github.com/thousandflowers/Parrot/actions/workflows/ci.yml/badge.svg)](https://github.com/thousandflowers/Parrot/actions) [![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)](https://github.com/thousandflowers/Parrot) [![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**Select text. Press ⌘⇧E. Done.**

Parrot is a macOS menu bar app that corrects your writing in any app - terminal, Xcode, Notion, Figma, anywhere — using a local AI model that never sends your text anywhere. No subscription. No browser extension. No cloud.

<!-- GIF: 10-second screen recording — select text in any app → ⌘⇧E → diff panel appears → press Return to apply. Trim to the essentials. -->
![Parrot in action](docs/demo.gif)

---

## Why I built this

Two reasons.

My girlfriend is Chinese. She writes in Italian every day emails,
messages, university assignments. She knows what she wants to say;
she just needs something to catch the grammar before she sends it.
Every tool she tried either required an account, sent her text to a
server she didn't choose, or simply didn't work in the app she was
already using.

I have dyslexia. Verb tenses, agreement, the small things that are
supposed to be automatic they're not, for me. I needed a correction
layer that works everywhere I write: terminal, Xcode, a chat window,
a commit message.

We needed the same thing: something quiet, offline, that works in
whatever app is already open, and disappears the moment you're done.
Nothing we found did all of that. So I built it.

---

## How it works

```
Select text in any app
        ↓
  ⌘⇧E
        ↓
Parrot reads it via the macOS Accessibility API
        ↓
Local LLM corrects it — 0 bytes leave your Mac
        ↓
Floating diff panel appears next to your cursor
        ↓
  Return — correction written back into the field
```

<!-- GIF: close-up of the diff panel — individual spans highlighted, accept/reject a single change. -->
![Diff panel](docs/diff-panel.gif)

No clipboard. No context switch. No copy-paste.

---

## Parrot vs. Grammarly vs. LanguageTool

|  | Parrot | Grammarly | LanguageTool |
|---|---|---|---|
| Works in every macOS app (terminal, Xcode, Figma…) | ✅ | ❌ | ❌ |
| Offline by default, 0 bytes sent | ✅ | ❌ | partial |
| No account, no subscription, no extension | ✅ | ❌ | partial |
| Per-app rules (different prompt per app) | ✅ | ❌ | ❌ |
| Accept/reject individual corrections | ✅ | ❌ | ❌ |
| Open source | ✅ | ❌ | ✅ |

---

## Get started

```bash
brew install --cask thousandflowers/parrot/parrot
```

Or [download the DMG](https://github.com/thousandflowers/Parrot/releases) and drag to `/Applications`.

**First launch on macOS:** if you see "unidentified developer", right-click → Open. A notarized build is in progress.

**Setup in 60 seconds:**
1. Launch Parrot — a small ✓ appears in your menu bar
2. Grant Accessibility access when prompted (System Settings → Privacy & Security → Accessibility)
3. Open Settings → Models → download `qwen2.5-1.5b` (~1 GB, fast on M1+)
4. Open Notes, type `"i writed this yesterday"`, select it, press ⌘⇧E

Want inline autocomplete instead of grammar correction? Install the sibling app:

```bash
brew install --cask thousandflowers/parrot/wren
```

---

## Features

**Correction modes** — Grammar, Fluency, Grammar+Fluency, Translate, Writing Coach, De-Slop (strips AI filler), AI Prompt Optimizer, and fully custom prompts. Bind any mode to a keyboard shortcut.

**Span-based diff panel** — Accept or reject individual corrections instead of the whole suggestion. Each span shows a source badge (⚡ rule · 🔤 LanguageTool · 📖 Harper · 🤖 LLM) and an inline reason.

**Hybrid correction engine** — Four layers, fastest first: deterministic rules → LanguageTool (500+ grammar rules, 25+ languages, fully offline) → Harper (advanced English, offline) → LLM (complex rewrites). The LLM only runs when the lighter layers aren't enough.

**StyleProfiler** — Detects your writing style and tone from a URL or pasted text, then adapts suggestions to match it.

**Learns your style — offline.** Every rejected correction is logged locally. After enough rejections it detects patterns and injects them as style notes into future prompts. No model retraining. No data leaves your Mac.

**Smart Expand** — Turns draft emails and short notes into full messages. Learns contact names from macOS Contacts.

**Inline annotations** — Real-time underlines as you pause typing, without triggering a shortcut. Hover to see the suggestion and apply with one click.

**Flows** — Chain multiple steps into a single action: grammar → simplify → translate to French. Save and trigger with a shortcut.

**Knowledge Base** — Store style guides, glossaries, brand voice examples. Parrot finds the most relevant entries and injects them as context into LLM prompts.

**Per-app rules** — Different prompt, backend, or language per app, by bundle ID.

**Backends** — llama.cpp (bundled, default), Apple Intelligence (macOS 26+), LanguageTool (offline), Harper (offline), Ollama, OpenAI, OpenRouter.

**Privacy** — iCloud sync for settings across your Macs. Local-only mode keeps everything on device. API keys stored in Keychain.

---

## Status

Current release: **v0.9.3 beta**

| Feature | Status |
|---|---|
| Grammar / Fluency / Translate / Coach / De-Slop / AI Prompt Optimizer | ✅ shipped |
| Span-based diff panel (per-fix accept/reject, source badges) | ✅ shipped |
| Hybrid engine: rules + LanguageTool + Harper + LLM | ✅ shipped |
| Inline annotations | ✅ shipped |
| StyleProfiler + offline style learning | ✅ shipped |
| Smart Expand | ✅ shipped |
| Knowledge Base + Flows + Story Analyzer | ✅ shipped |
| Per-app rules, custom regex rules, presets | ✅ shipped |
| Apple Intelligence backend (macOS 26) | ✅ shipped |
| iCloud sync | ✅ shipped |
| Homebrew cask | ✅ shipped |
| Notarized release | ◻︎ in progress |
| Mac App Store | ◻︎ planned |

---

## Architecture

Swift/SwiftUI app with actor-based shared state (zero data races by construction). AI inference runs via a bundled `llama-server` subprocess — no Ollama dependency, no always-on daemon, no port conflicts. Text is read and written via `AXUIElement` APIs directly into the focused UI element.

See [`docs/architecture.md`](docs/architecture.md) for module structure, the macOS 26 constraint-loop fix, and design decisions.

---

## Build from source

```bash
git clone https://github.com/thousandflowers/Parrot
cd Parrot
swift build -c release
./build-app.sh release   # produces Parrot.app + Parrot.dmg
```

Requirements: macOS 14+, Xcode 16 / Swift 5.10.

---

## Contributing

- Bug report → [open an issue](https://github.com/thousandflowers/Parrot/issues)
- Feature idea → [open a discussion](https://github.com/thousandflowers/Parrot/discussions)
- Easy first tasks → [`good first issue`](https://github.com/thousandflowers/Parrot/labels/good%20first%20issue)

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## License

MIT — see [LICENSE](LICENSE).
