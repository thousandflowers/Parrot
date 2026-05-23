# Parrot

[![CI](https://github.com/thousandflowers/Parrot/actions/workflows/ci.yml/badge.svg)](https://github.com/thousandflowers/Parrot/actions)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square)
![macOS 26](https://img.shields.io/badge/macOS-26_Tahoe-blue?style=flat-square)
![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange?style=flat-square)
![License: MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square)
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
- **Writers** — polish tweets, Substack posts, or newsletter drafts in any editor, with one shortcut. Use the Story Analyzer for manuscript-level feedback.
- **Non-native speakers** — get instant feedback on phrasing in your second language, with full offline privacy.

---

## How it works

```
Select text in any app  →  ⌘⇧E  →  Review panel  →  Return to apply
```

Parrot uses the macOS Accessibility API to read and write text directly in the focused element — no clipboard hijacking, no context switch. The LLM runs locally by default (bundled `llama-server`), so text never leaves your Mac.

---

## Performance & privacy

| | Local (llama.cpp) | Apple Intelligence | Ollama | OpenAI / OpenRouter |
|---|---|---|---|---|
| Avg. latency on M2 | ~3s (1.5B model) | ~1–2s | ~3–5s | ~1–2s |
| Data sent externally | **0 bytes** | **0 bytes** | **0 bytes** | Text sent to provider |
| Internet required | No | No | No | Yes |
| Setup | Download model in Settings | macOS 26+ with Apple Intelligence enabled | Ollama + model installed | API key in Settings |

> In local and Apple Intelligence mode, **nothing leaves your Mac** — no text, no metadata, no analytics. With OpenAI or OpenRouter, your text passes through their servers according to their privacy policies.

Recommended model for everyday use: `qwen2.5-1.5b-instruct-q4_k_m.gguf` (~1 GB, fast enough for real-time mode on M1+).

---

## Install

### Download the app

1. Download **[Parrot.dmg](https://github.com/thousandflowers/Parrot/releases/latest)** from the Releases page
2. Open the DMG, drag Parrot to `/Applications`
3. Launch Parrot — a **✓** appears in your menu bar
4. Grant **Accessibility** permission when prompted *(System Settings → Privacy & Security → Accessibility)*
5. In Settings, download a model or enter an API key

> First launch: macOS may warn "unidentified developer". Right-click the app → **Open** to bypass Gatekeeper (ad-hoc signed build). A notarized release is planned.

### Homebrew

```bash
brew install --cask thousandflowers/parrot/parrot
```

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

### Suggestion panel
- **Diff highlight** — changed words shown in green so you see exactly what changed
- **Side-by-side diff** — toggle between inline diff and clean result view
- **Explain** — ask the model to justify each correction inline
- **Text-to-speech** — hear the corrected version before applying
- **Undo** — 5-second revert window after applying
- **Translate** — translate directly from the panel to any language
- **Custom actions** — run any prompt on the current text from the panel

### Flows
Chain multiple correction steps into a single action — e.g. *grammar → simplify → translate*. Flows run sequentially; the output of each step feeds the next. Bind a flow to a custom shortcut or trigger it from the panel.

### Floating Editor
Full-screen split editor with original and corrected text side by side. Supports:
- **Dictation** — click the microphone to dictate directly into the input pane
- **File import** — import `.txt`, `.rtf`, or plain text files
- **Story analysis** — for texts over 100 words, analyze narrative structure, pacing, character, and style

### Story Analyzer
Manuscript-level feedback for longer texts: scores overall quality, pacing, character development, dialogue, and style. Shows per-category scores with actionable feedback.

### Plagiarism Detector
Check text for potential plagiarism against web sources, your Knowledge Base, and an LLM style analysis. Returns a similarity score and matched passages.

### Knowledge Base
Store reference documents, style guides, or snippets. The LLM uses them as context for corrections — useful for domain-specific vocabulary or house style.

### Intelligence
- **Language auto-detection** — adapts the prompt to the text's language automatically (50+ languages)
- **Apple Intelligence backend** — use macOS 26's on-device `FoundationModels` as the LLM (no download required, fully private)
- **Per-app rules** — different model, tone, or prompt for each application
- **Real-time mode** — auto-checks when you pause typing (optional, off by default)
- **Correction history** — browse and re-apply past corrections in Settings
- **Custom prompts** — reusable templates with hotkey bindings
- **Ignore list** — words Parrot should never flag or change

### Sync & backup
- **iCloud sync** — sync preferences, correction history, and custom rules across all your Macs
- **Export / Import** — back up or transfer settings as JSON

---

## Why not Grammarly / LanguageTool?

| | Parrot | Grammarly | LanguageTool |
|---|---|---|---|
| Works in every app (terminal, Xcode, Figma…) | ✅ | ❌ | ❌ |
| Fully offline by default | ✅ | ❌ | partial |
| Apple Intelligence backend (macOS 26) | ✅ | ❌ | ❌ |
| No daemon, no browser extension | ✅ | ❌ | ❌ |
| Per-app rules | ✅ | ❌ | ❌ |
| Custom prompts & flows | ✅ | ❌ | ❌ |
| No subscription | ✅ | ❌ | partial |
| Open source | ✅ | ❌ | ✅ |

---

## Architecture

```
Parrot/
├── App/           AppDelegate, Constants, AppUpdater (Sparkle)
├── Core/          LLMService, PromptEngine, RequestQueue, CorrectionResult,
│                  HistoryStore, Flow, KnowledgeBase, StoryAnalyzer,
│                  PlagiarismDetector, DictationService, AppleIntelligenceService
├── Accessibility/ AXUIElement bridge, AppDetector, clipboard fallback
├── Shortcuts/     Carbon global hotkey registration
├── UI/            MenuBarView, SuggestionPanel, FloatingEditor, SettingsView tabs,
│                  StoryAnalysisSheet, SideBySideDiffView, InlineHighlightController
├── Infra/         Keychain, ModelManager, ServerManager (llama-server),
│                  ExportImportManager, iCloudSyncManager, PreferencesStore
├── ObjCBridge/    NSWindowConstraintLoopFix (macOS 26 constraint-loop crash fix)
└── Resources/     Info.plist, entitlements, localizations (7 languages)
```

**Design decisions:**
- Swift `actor` for every piece of shared mutable state — zero data races by construction
- `llama-server` spawned as a managed subprocess — no Ollama dependency, no daemon, no port conflicts
- `AXUIElement` API writes text directly into the focused element; clipboard injection is the fallback
- `PromptEngine` detects the text's language via `NLLanguageRecognizer` and selects the appropriate system prompt automatically
- ObjC runtime swizzle (`NSWindowConstraintLoopFix.m`) defers re-entrant `setNeedsUpdateConstraints:` calls on macOS 26, preventing the NSGenericException/SIGABRT that AppKit introduced in the Tahoe beta

---

## macOS 26 Tahoe compatibility

Parrot fully supports macOS 26 (Tahoe). The ObjC bridge (`ObjCBridge/NSWindowConstraintLoopFix.m`) patches a regression in AppKit where `NSHostingView.updateConstraints` → `updateWindowContentSizeExtremaIfNecessary` re-enters `setNeedsUpdateConstraints:` inside the same constraint pass, causing `NSGenericException` → `objc_exception_rethrow` → SIGABRT. The fix defers all re-entrant calls process-wide via `dispatch_async`, which is the only approach that also covers system-owned status bar windows.

---

## Roadmap

- [ ] Notarized release (proper Gatekeeper pass, no right-click needed)
- [x] PopClip extension — select text in PopClip → correct with one tap
- [x] iCloud sync for custom rules and history
- [x] Homebrew cask (`brew install --cask parrot`)
- [x] Apple Intelligence backend (macOS 26+)
- [x] Flows — multi-step correction pipelines
- [x] Story Analyzer — manuscript-level writing feedback
- [x] Plagiarism Detector
- [x] Knowledge Base
- [ ] Native TTS voices per language
- [ ] Mac App Store release

---

## Requirements

- macOS 14.0 Sonoma or later (macOS 26 Tahoe fully supported)
- Apple Silicon (M1 or newer) recommended; Intel + Metal GPU supported
- 4 GB RAM minimum; 16 GB recommended for 3B+ parameter models
- Accessibility permission (Privacy & Security → Accessibility)

---

## Privacy

- **Offline by default** — local LLM inference, zero network requests
- **No telemetry** — no analytics, no crash reporting, no data collection of any kind
- **API keys in Keychain** — stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, never written to disk
- **Feedback log** — optional, local only: `~/Library/Application Support/Parrot/feedback.jsonl`, text truncated to 500 chars, never uploaded
- **Correction history** — stored locally at `~/Library/Application Support/Parrot/history.json`; optionally synced via iCloud (encrypted in transit)

---

## Contributing

Found a bug? [Open a bug report](https://github.com/thousandflowers/Parrot/issues/new?template=bug_report.md).
Have an idea? [Open a feature request](https://github.com/thousandflowers/Parrot/issues/new?template=feature_request.md).
Looking for something easy to start with? Check [good first issues](https://github.com/thousandflowers/Parrot/labels/good%20first%20issue).

Pull requests welcome. Please open an issue first for non-trivial changes. See [CONTRIBUTING.md](CONTRIBUTING.md).

```bash
swift test                              # run all tests
swift test --filter PromptEngineTests   # run a specific suite
swift build                             # debug build
```

---

## License

MIT — see [LICENSE](LICENSE).
