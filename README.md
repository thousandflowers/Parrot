# Parrot

[![CI](https://github.com/thousandflowers/Parrot/actions/workflows/ci.yml/badge.svg)](https://github.com/thousandflowers/Parrot/actions) [![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)](https://github.com/thousandflowers/Parrot) [![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE) [![Sponsor](https://img.shields.io/github/sponsors/thousandflowers?label=Sponsor)](https://github.com/sponsors/thousandflowers)

**⌘⇧E. Grammar fixed. Any app. Offline. Zero bytes sent.**

<!-- GIF: 10-second screen recording — select text in any app → ⌘⇧E → diff panel appears → press Return to apply -->
![Parrot in action](docs/demo.gif)

---

## Why I built this

Two reasons.

My girlfriend is Chinese. She writes in Italian every day — emails, messages, university assignments. She knows what she wants to say; she just needs something to catch the grammar before she sends it. Every tool she tried either required an account, sent her text to a server she didn't choose, or simply didn't work in the app she was already using.

I have dyslexia. Verb tenses, agreement, the small things that are supposed to be automatic — they're not, for me. I needed a correction layer that works everywhere I write: terminal, Xcode, a chat window, a commit message.

We needed the same thing: something quiet, offline, that works in whatever app is already open, and disappears the moment you're done. Nothing we found did all of that. So I built it.

---

## Quickstart

```bash
brew install --cask thousandflowers/parrot/parrot
```

Or [download the DMG](https://github.com/thousandflowers/Parrot/releases/latest) and drag to `/Applications`.

**First launch on macOS:** if you see "unidentified developer", right-click → Open. A notarized build is in progress.

1. Launch Parrot — a small ✓ appears in your menu bar
2. Grant Accessibility access when prompted (System Settings → Privacy & Security → Accessibility)
3. Open Settings → Models → download `qwen2.5-1.5b` (~1 GB, fast on M1+)
4. Open Notes, type `"i writed this yesterday"`, select it, press ⌘⇧E

Want inline autocomplete instead? Install the sibling app:

```bash
brew install --cask thousandflowers/parrot/wren
```

---

## How it works

Parrot is a hybrid correction engine with 4 layers — fastest first, LLM only when needed:

| Layer | What it does | Speed |
|---|---|:---:|
| ⚡ Deterministic rules | Obvious errors (spaces, apostrophes, caps) | instant |
| 🔤 LanguageTool | 500+ grammar rules, 25+ languages, fully offline | <50ms |
| 📖 Harper | Advanced English grammar (Rust binary, offline) | <100ms |
| 🤖 Local LLM | Complex rewrites, fluency, style | 1–3s |

Each layer only runs if the previous one isn't enough. The LLM is never called to fix a missing apostrophe.

<!-- GIF: close-up of the diff panel — individual spans highlighted, accept/reject a single change -->
![Diff panel](docs/diff-panel.gif)

```
Select text in any app
        ↓
  ⌘⇧E
        ↓
Parrot reads it via the macOS Accessibility API
        ↓
Hybrid engine corrects it — 0 bytes leave your Mac
        ↓
Floating diff panel appears next to your cursor
        ↓
  Return — correction written back into the field
```

No clipboard. No context switch. No copy-paste.

---

## Parrot vs. everything else

|  | **Parrot** | Grammarly | LanguageTool | WritingTools | TextWarden |
|---|---|---|---|---|---|
| Works in every macOS app (terminal, Xcode, Figma…) | ✅ | ❌ | ❌ | ✅ | ✅ |
| Offline, 0 bytes sent | ✅ | ❌ | partial | ✅ | ✅ |
| Hybrid rules + LT + Harper + LLM | ✅ | ❌ | ❌ | ❌ | ❌ |
| Accept/reject individual corrections (span diff) | ✅ | ❌ | ❌ | ❌ | ❌ |
| Per-app rules | ✅ | ❌ | ❌ | ❌ | ❌ |
| Flows (multi-step chains) | ✅ | ❌ | ❌ | ❌ | ❌ |
| Personal Knowledge Base | ✅ | ❌ | ❌ | ❌ | ❌ |
| No account, no subscription | ✅ | ❌ | ❌ | ✅ | ✅ |
| Open source | ✅ | ❌ | ✅ | ✅ | ✅ |

---

## Features

**Correction modes** — Grammar, Fluency, Grammar+Fluency, Translate, Writing Coach, De-Slop (strips AI filler), AI Prompt Optimizer, and fully custom prompts. Bind any mode to a keyboard shortcut.

**Span-based diff panel** — Accept or reject individual corrections instead of the whole suggestion. Each span shows a source badge (⚡ rule · 🔤 LanguageTool · 📖 Harper · 🤖 LLM) and an inline reason.

**StyleProfiler** — Detects your writing style and tone from a URL or pasted text, then adapts suggestions to match it.

**Learns your style — offline.** Every rejected correction is logged locally. After enough rejections it detects patterns and injects them as style notes into future prompts. No model retraining. No data leaves your Mac.

**Smart Expand** — Turns draft notes and short email stubs into full messages. Learns contact names from macOS Contacts.

**Inline annotations** — Real-time underlines as you pause typing, without triggering a shortcut. Hover to see the suggestion and apply with one click.

**Flows** — Chain multiple steps into a single action: grammar → simplify → translate to French. Save and trigger with a shortcut.

**Knowledge Base** — Store style guides, glossaries, brand voice examples. Parrot finds the most relevant entries and injects them as context into LLM prompts.

**Per-app rules** — Different prompt, backend, or language per app, by bundle ID.

---

## Backends

| Backend | Default? | Offline? | Setup |
|---|:---:|:---:|---|
| llama.cpp (bundled) | ✅ | ✅ | Download model from Settings |
| Apple Intelligence | auto-fallback on macOS 26 | ✅ | Automatic |
| LanguageTool (bundled) | part of hybrid layer | ✅ | Zero setup |
| Harper (bundled) | part of hybrid layer | ✅ | Zero setup |
| Ollama | ❌ | ✅ | `brew install ollama` |
| OpenAI / OpenRouter | ❌ | ❌ | API key in Settings |

---

## Status

Current release: **v0.9.3 beta**

| Feature | Status |
|---|:---:|
| Grammar / Fluency / Translate / Coach / De-Slop / AI Prompt Optimizer | ✅ |
| Span-based diff panel (per-fix accept/reject, source badges) | ✅ |
| Hybrid engine: rules + LanguageTool + Harper + LLM | ✅ |
| Inline annotations | ✅ |
| StyleProfiler + offline style learning | ✅ |
| Smart Expand + Contacts integration | ✅ |
| Knowledge Base + Flows + Story Analyzer | ✅ |
| Per-app rules, custom regex rules, presets | ✅ |
| Apple Intelligence backend (macOS 26) | ✅ |
| iCloud sync | ✅ |
| Homebrew cask | ✅ |
| Notarized release | ◻︎ in progress |
| Mac App Store | ◻︎ planned |

---

## Architecture

Swift/SwiftUI with actor-based shared state (zero data races by construction). AI inference runs via a bundled `llama-server` subprocess — no Ollama dependency, no always-on daemon, no port conflicts. Text is read and written via `AXUIElement` APIs directly into the focused UI element.

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
