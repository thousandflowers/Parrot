# Parrot — Launch Materials

## Product Hunt

### Tagline
> Grammar and style correction for every app on your Mac — offline, instant, no subscription

### Description
Parrot is a menu bar app that fixes your grammar and style in any app — Mail, Slack, VS Code, Terminal, Figma, anywhere. Select text, press ⌘⇧E, and a floating panel shows the corrected version with diff highlighting. One keypress applies it.

Unlike Grammarly or LanguageTool, Parrot works system-wide via macOS Accessibility API — no browser extension, no daemon, no context switching. The LLM runs locally by default (bundled llama-server), so your text never leaves your Mac.

**Key features:**
- 🔒 Fully offline — bundled llama-server, zero network requests
- ⚡ Works in every app — Terminal, Xcode, Figma, Slack, Mail, anywhere
- 🎯 4 modes — Grammar, Fluency, Translate, Writing Coach
- 🌍 50+ languages — auto-detects and adapts prompts
- 🎨 Diff highlight + Explain — see exactly what changed, ask why
- 🏷️ Free & open source (MIT) — no subscription, no account

**Why now?** AI writing tools are everywhere, but they all require sending your text to the cloud. Parrot proves you can have powerful grammar correction with complete privacy — running entirely on your Mac's neural engine.

### Maker Comment (first comment)
> Hey PH! I built Parrot because I was tired of copying text into ChatGPT or Grammarly just to fix a paragraph. I wanted something that works in my terminal, my code editor, my email client — everywhere I write — without sending my text to a server.
>
> Parrot uses a bundled llama-server subprocess (no Ollama needed) that runs entirely locally. It detects the language automatically, shows you a diff of what changed, and lets you apply corrections with one keypress.
>
> It's MIT-licensed and free forever. Would love your feedback!
>
> Tech stack: Swift/SwiftUI, llama.cpp, macOS Accessibility API

### Topics
- Developer Tools
- Productivity
- Artificial Intelligence
- Mac
- Open Source
- Writing
- Privacy

---

## Hacker News (Show HN)

### Title
> Show HN: Parrot – Offline grammar correction for every app on your Mac (Swift, MIT)

### Post Content (optional comment)
Parrot is a menu bar app that corrects grammar and style in any macOS application. Select text, press ⌘⇧E, review the diff, press Return to apply.

Key design decisions:
- Bundled llama-server as a managed subprocess — no Ollama dependency, no daemon, no port conflicts
- AXUIElement API writes text directly into the focused element — no clipboard hijacking
- PromptEngine detects text language via NLLanguageRecognizer and selects appropriate system prompts
- Swift actor for every piece of shared mutable state — zero data races by construction
- Zero telemetry, zero analytics, zero data collection

Works in 50+ languages with 4 correction modes (grammar, fluency, translate, writing coach). Custom prompts with hotkey bindings.

Source: https://github.com/thousandflowers/Parrot

---

## Reddit (r/macapps, r/MacOS, r/selfhosted)

### Title
> I built a free, offline grammar checker for Mac that works in every app (not just browsers)

### Post Body
Hey everyone, I built Parrot — a menu bar app that corrects grammar and style in any app on your Mac.

**The problem:** Grammarly and LanguageTool only work in browsers and a few native apps. They don't work in Terminal, Xcode, Figma, or most desktop apps. And they all send your text to the cloud.

**The solution:** Parrot uses macOS Accessibility API to read and write text directly in the focused element. The LLM runs locally via a bundled llama-server, so nothing leaves your Mac.

**How it works:**
1. Select text in any app
2. Press ⌘⇧E
3. Review the correction panel (diff highlighting, explain, TTS)
4. Press Return to apply

**Features:**
- Fully offline (bundled llama-server)
- Works in every app (Terminal, Xcode, Figma, Slack, Mail...)
- 4 modes: Grammar, Fluency, Translate, Writing Coach
- 50+ languages with auto-detection
- Custom prompts with hotkey bindings
- Free and open source (MIT)

**Download:** https://github.com/thousandflowers/Parrot/releases/latest

Would love feedback, especially from non-native English speakers and people who write a lot in non-browser apps.

---

## Twitter / X Launch Thread

**Tweet 1:**
🦜 Introducing Parrot — grammar and style correction for every app on your Mac.

Select text anywhere → press ⌘⇧E → corrected text appears.

Offline. No subscription. Open source.

https://github.com/thousandflowers/Parrot

**Tweet 2:**
Why Parrot?

Grammarly doesn't work in Terminal.
LanguageTool doesn't work in Xcode.
ChatGPT requires copy-pasting.

Parrot works everywhere via macOS Accessibility API. No browser extension. No daemon. No context switching.

**Tweet 3:**
Privacy by construction:

🔒 Bundled llama-server runs locally
📡 Zero network requests by default
🔑 API keys in Keychain
📊 No telemetry, no analytics
✈️ Works on a plane

Your text never leaves your Mac.

**Tweet 4:**
4 correction modes:

⌘⇧E Grammar — spelling, grammar, punctuation
⌘⇧T Fluency — clarity without changing meaning
⌘⇧U Translate — EN/IT/ES/FR/DE
⌘⇧W Writing Coach — structural improvements

Plus custom prompts with your own hotkeys.

**Tweet 5:**
Built with Swift/SwiftUI, llama.cpp, and macOS Accessibility API.

MIT licensed. Free forever.

Try it: https://github.com/thousandflowers/Parrot/releases/latest

Feedback welcome! 🙏

---

## Timeline

| Day | Action |
|---|---|
| Day -3 | Finalize notarized build, test on clean Mac |
| Day -2 | Prepare screenshots, record demo GIF |
| Day -1 | Submit to Product Hunt (schedule for 12:01 AM PT) |
| Day 0 | Post Show HN at 10:00 AM PT, tweet thread, Reddit posts |
| Day +1 | Respond to all comments, engage with feedback |
| Day +2 | Follow-up posts on Indie Hackers, Lobsters |
| Day +7 | Share metrics and learnings, thank community |
