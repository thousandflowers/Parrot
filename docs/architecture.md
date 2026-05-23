# Parrot — Architecture

## Module structure

```
Parrot/
├── App/           AppDelegate, Constants, AppUpdater (Sparkle)
├── Core/          LLMService protocol + backends, PromptEngine, RequestQueue,
│                  CorrectionResult, HistoryStore, Flow, KnowledgeBase,
│                  StoryAnalyzer, PlagiarismDetector, DictationService,
│                  AppleIntelligenceService
├── Accessibility/ AXUIElement bridge (read/write selected text),
│                  AppDetector (per-app rules), ElectronFallbackHandler
├── Shortcuts/     Carbon global hotkey registration
├── UI/            MenuBarView, SuggestionPanel (floating diff panel),
│                  FloatingEditor, SettingsView + all settings tabs,
│                  StoryAnalysisSheet, SideBySideDiffView,
│                  InlineHighlightController, HoverAnnotationPopup
├── Infra/         KeychainService, ModelManager, ServerManager (llama-server),
│                  PreferencesStore, ExportImportManager, iCloudSyncManager,
│                  ServerHealthMonitor, CrashLogger
├── ObjCBridge/    NSWindowConstraintLoopFix.m (macOS 26 crash fix — see below)
└── Resources/     Info.plist, entitlements, localizations (7 languages)
```

## Key design decisions

**Swift actors everywhere.** Every piece of shared mutable state — `RequestQueue`, `HistoryStore`, `ModelManager`, `KnowledgeBase`, `PreferencesStore` — is a Swift `actor`. This eliminates data races by construction and avoids manual locking.

**llama-server as a managed subprocess.** The bundled `llama-server` binary is spawned by `ServerManager` as a child process bound to a random localhost port. This means no always-on daemon, no Ollama dependency, no port conflicts, and clean shutdown when the app quits.

**AXUIElement API for text I/O.** Parrot reads selected text and writes corrections directly into the focused UI element via `AXUIElement`. This works in every app that exposes standard macOS accessibility — including terminals, native editors, and most Electron apps. Clipboard injection is the fallback for apps that don't.

**PromptEngine + language detection.** `PromptEngine` calls `NLLanguageRecognizer` on the input text to detect its language (50+ supported), then selects and renders the appropriate system prompt. The same mechanism powers per-app rule overrides from `PreferencesStore`.

**RequestQueue with priority lanes.** Requests are queued and dispatched through `RequestQueue` with priority levels (`manual` > `floatingEditor` > `realtime`). Manual corrections (user-triggered shortcut) always preempt real-time background checks.

## macOS 26 Tahoe — constraint loop crash fix

macOS 26 introduced a regression in how `NSHostingView` (the SwiftUI ↔ AppKit bridge) handles layout passes.

**Root cause:** `NSHostingView.updateConstraints` calls `updateWindowContentSizeExtremaIfNecessary`, which triggers SwiftUI's graph reconciliation, which calls `setNeedsUpdateConstraints(true)` — *inside* the same constraint pass. AppKit's re-entrancy guard throws `NSGenericException`. AppKit's display-cycle observer calls `objc_exception_rethrow`, which calls C++ `terminate`, which raises SIGABRT.

**Why it crashes Parrot specifically:** macOS 26 uses `NSHostingView` internally for the system status bar button window (the `{102, 26}` window in crash logs). This is a system-owned window — we can't subclass it. Our Swift `FixedSizeHostingView` subclass protects our own windows but not this one.

**Fix — `ObjCBridge/NSWindowConstraintLoopFix.m`:**

The ObjC file swizzles three methods at `+load` time (before `main()`):

1. `NSWindow.updateConstraintsIfNeeded` — wraps the original in `@try/@catch` that suppresses only `NSGenericException` with constraint-related reasons, and marks the window as "in a constraint pass" in a global `NSMutableSet`.
2. `NSWindow.layoutIfNeeded` — same treatment.
3. `NSView.setNeedsUpdateConstraints:` — if the call arrives with `flag = YES` while the view's window is in the "in a constraint pass" set, the call is **deferred** via `dispatch_async(main_queue)` instead of being dropped. This is the key: SwiftUI needs the deferred call to complete its rendering pass. Dropping the call leaves the panel empty.

The swizzle runs process-wide, covering system-owned windows too. It uses ARC-compatible `(__bridge void *)` casts and `dispatch_once` for thread safety.

**Why `@try/@catch` alone is not enough:** catching the exception in `updateConstraintsIfNeeded` and returning leaves the window in a "needs layout" state. On the next display-cycle tick the same exception fires again → infinite suppression loop → window never processes mouse events (menu bar icon appears frozen).

## LLM backends

| Backend | Class | Notes |
|---|---|---|
| llama.cpp (bundled) | `LocalLLMService` | Default. `ServerManager` spawns `llama-server` on demand. |
| Apple Intelligence | `AppleIntelligenceService` | `@available(macOS 26)`. Uses `FoundationModels.LanguageModelSession`. |
| Ollama | `OllamaService` | Connects to local Ollama instance. |
| OpenAI / OpenRouter | `RemoteLLMService` | Streaming via `URLSession`. API key in Keychain. |
| Stub | `StubLLMService` | Deterministic responses for unit tests. |

`LLMServiceFactory.make()` resolves the correct backend based on `PreferencesStore.serviceType` and availability at runtime.
