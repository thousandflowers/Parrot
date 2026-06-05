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

Prefer inline completion instead of grammar correction? Install **Wren** (the on-device autocomplete sibling, ships from the same releases):
```bash
brew install --cask thousandflowers/parrot/wren
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

## Wren — works in (inline completion)

Wren reads the focused field via the macOS Accessibility API to offer context-aware completion; where a field can't be read it falls back to a typed-input buffer (completes from what you type, but can't see pre-existing text). Verdicts below are self-verifiable: in Wren open **Settings → Advanced → App compatibility → Check last focused app** while a text field is focused in the target app.

| App | Status |
|---|---|
| TextEdit | ✅ Full |
| Notes | ✅ Full |
| Pages | _to verify_ |
| Mail | _to verify_ |
| Safari | _to verify_ |
| Chrome | _to verify (Chromium AX)_ |
| Slack | _to verify (Electron AX)_ |
| Messages | _to verify_ |
| Telegram | _to verify_ |
| Outlook | _to verify_ |
| Bear | _to verify_ |
| Notion | _to verify (Electron AX)_ |
| VS Code | _to verify (Electron AX)_ |
| Terminal | ⚠️ Partial (typed-only) |

> Legend: **✅ Full** = context-aware (reads the field) · **⚠️ Partial** = typed-only fallback · **🔒 Secure** = password fields, never completed by design.

---

## Features

**Correction modes** — Grammar, Fluency, Grammar+Fluency combined, Translate, Writing coach, De-Slop (strips AI hedging and filler), AI Prompt Optimizer (reformats text into a cleaner prompt), and fully custom prompts. Bind any mode to a keyboard shortcut.

**Span-based diff panel** — Each correction is a standalone span: accept or reject individual changes instead of the whole suggestion. Every span shows a source badge (⚡ deterministic rule, 🔤 LanguageTool, 📖 Harper, 🤖 LLM) and an inline reason. Toggle to a clean result view. One-click apply, explain, translate, or undo.

**Hybrid correction engine** — Four layers, no unnecessary LLM calls: deterministic rules for obvious errors → LanguageTool for 500+ grammar rules across 25+ languages (fully offline) → Harper for advanced English grammar (offline binary) → LLM for complex rewrites. Each layer only runs when the previous one isn't enough.

**StyleProfiler** — Detects your writing style (formal, conversational, technical, narrative) and tone from a browser URL or pasted text, then adapts suggestions to match it.

**Learns your style — offline.** Every time you reject a correction, Parrot logs the pair locally in `~/Library/Application Support/Parrot/feedback.jsonl`. After enough rejections it detects patterns (e.g. you always reject *"qui" → "qua"*) and injects them as a style note into future LLM prompts — so the same correction is not suggested again. No model is retrained; no data leaves your Mac. The log is capped at 10 MB and rotated automatically.

**Smart Expand** — Detects draft emails and short notes, learns contact names from your macOS Contacts, and expands them into full messages with the right tone and length.

**Inline annotations** — Real-time underlines appear as you pause typing, without needing to trigger a shortcut. Hover over an underline to see the suggestion and apply it with one click. Deep accessibility tree scanning can be toggled per app. Enable hover-only mode to keep underlines invisible until you need them.

**Flows** — Chain multiple steps into a single action: *grammar → simplify → translate to French*. Save flows and trigger them with a shortcut.

**Knowledge Base** — Store reference documents (style guides, glossaries, brand voice examples). Parrot automatically finds the most relevant entries for your current text and injects them as context into LLM prompts, so suggestions stay consistent with your terminology.

**Plagiarism detection** — Checks text against your Knowledge Base (Jaccard similarity), and optionally uses the LLM to identify AI-generated patterns and copied phrasing.

**Floating Editor** — A full split-screen editor for longer texts. Includes dictation input (macOS Speech framework), file import, and a **Story Analyzer** that scores narrative structure, pacing, and style for manuscripts over 100 words.

**Per-app rules** — Assign a different prompt, backend, or language to any app by bundle ID. Add the frontmost app with one click. Enable or disable rules without deleting them.

**Custom rules** — Define regex patterns with backreference support, case sensitivity, and per-language filtering. Applied before any LLM call.

**Presets** — Save language + model + temperature combinations and bind them to shortcuts for instant switching.

**Export / Import** — Back up or share your entire configuration as JSON. Choose exactly which sections to include: Flows, Custom Prompts, Presets, App Rules, Shortcuts, Preferences.

**Intelligence** — Language auto-detection (50+ languages, with CJK and RTL optimizations), real-time mode, correction history (200 entries), ignore list, response caching. Grammar mode targets minimum changes and preserves verb tense, mood, gender, and voice. Smart translation target detection infers target language from context (browser URL, app name, surrounding text) without a setting to configure.

**Privacy and sync** — iCloud sync for settings and history across your Macs. Local-only mode keeps everything on device. API keys stored in Keychain, never on disk.

**Backends** — llama.cpp (bundled, default), Apple Intelligence (macOS 26+, automatic fallback when llama-server is unavailable), LanguageTool (offline, bundled), Harper (offline, bundled), Ollama, OpenAI, OpenRouter. Model downloads from HuggingFace with optional token support (speeds downloads from ~500 KB/s to ~50 MB/s).

---

## Status

**Current release: 0.9.3**

| Feature | Status |
|---|---|
| Grammar / Fluency / Translate / Coach / De-Slop / AI Prompt Optimizer | ✔ shipped |
| Span-based diff panel (per-fix accept/reject, source badges) | ✔ shipped |
| Hybrid engine: rules + LanguageTool + Harper + LLM | ✔ shipped |
| Inline annotations (real-time underlines, hover popup) | ✔ shipped |
| StyleProfiler + offline style learning from rejections | ✔ shipped |
| Smart Expand — draft-to-full-email with Contacts integration | ✔ shipped |
| Smart translation target detection | ✔ shipped |
| Knowledge Base with context injection | ✔ shipped |
| Plagiarism detection | ✔ shipped |
| Flows, Story Analyzer | ✔ shipped |
| Per-app rules, Custom rules (regex), Presets | ✔ shipped |
| Export / Import configuration (JSON) | ✔ shipped |
| Offline local LLM (llama-server bundled) | ✔ shipped |
| Apple Intelligence backend (macOS 26, auto-fallback) | ✔ shipped |
| iCloud sync | ✔ shipped |
| Homebrew cask | ✔ shipped |
| Animated menu bar icon | ✔ shipped |
| Notarized release (no right-click needed) | ◻︎ in progress |
| Mac App Store | ◻︎ planned |

### What's new in 0.9.3

- **Span-based UI** — accept or reject individual corrections instead of the whole suggestion; each span shows its source (⚡ rule / 🔤 LanguageTool / 🤖 LLM) and a reason
- **LanguageTool integration** — 500+ grammar rules, 25+ languages, runs fully offline with no extra download
- **Hybrid pipeline** — deterministic rules → LanguageTool → LLM, so fast rules fire instantly and the LLM is only called when needed
- **StyleProfiler** — detects your writing tone from a URL or sample text, adapts suggestions to match your style
- **Smart Expand** — turns draft notes and short email stubs into full messages; learns contact names from macOS Contacts
- **Smart translation target** — infers target language from browser URL, app context, and recent messages; no manual language setting needed
- **Apple Intelligence auto-fallback** — if llama-server fails to start, Parrot falls back to Apple Intelligence on macOS 26 automatically
- **Animated menu bar bird** — the menu bar icon animates while a correction is in progress

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
