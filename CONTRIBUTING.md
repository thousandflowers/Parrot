# Contributing to Parrot

Thanks for your interest in contributing! Parrot is open source (MIT) and welcomes contributions of all kinds.

## Getting Started

### Requirements
- macOS 14.0 (Sonoma) or later
- Xcode 16+ or Swift 5.10 toolchain
- `llama.cpp` installed via Homebrew (for local mode): `brew install llama.cpp`

### Building
```bash
git clone https://github.com/thousandflowers/Parrot
cd Parrot
swift build                    # Debug build
swift build -c release         # Release build
swift test                     # Run all tests
swift test --filter PromptEngineTests  # Run a specific suite
```

To create a `.app` bundle:
```bash
./build-app.sh release
```

### Project Structure
```
Parrot/
├── App/              AppDelegate, Sparkle updater, constants
├── Core/             LLM services, prompt engine, correction logic
├── Accessibility/    AXUIElement bridge, app detection
├── UI/               Menu bar, suggestion panel, settings, onboarding
├── Infra/            Keychain, model/server management, caching
├── Shortcuts/        Global hotkey registration (Carbon)
├── Resources/        Info.plist, entitlements, localizations
├── Tests/            Unit and integration tests
└── PopClip/          PopClip extension
```

## How to Contribute

### 1. Find Something to Work On
- Check [good first issues](https://github.com/thousandflowers/Parrot/labels/good%20first%20issue) for beginner-friendly tasks
- Look at the [roadmap](README.md#roadmap) for planned features
- Found a bug? [Open an issue](https://github.com/thousandflowers/Parrot/issues/new?template=bug_report.md)

### 2. Make Your Changes
- Create a branch: `git checkout -b feat/your-feature`
- Follow existing code style (Swift 5.10, actors for shared state)
- Add tests for new functionality
- Keep changes focused — one feature/fix per PR

### 3. Submit a PR
- Open a pull request against `main`
- Describe what you changed and why
- Link any related issues
- Make sure `swift build` and `swift test` pass

### Code Conventions
- **Swift 5.10+** with strict concurrency (`Sendable` actors)
- **Actors** for all shared mutable state
- **`MainActor`** for UI code
- **No `as any` or `@unchecked Sendable`** unless absolutely necessary
- **Prefer `struct` over `class`** except for `NSWindow`/`NSPanel` controllers
- **Localize all user-facing strings** with `String(localized:)`

## Good First Contributions

| Area | Difficulty | Description |
|---|---|---|
| Add a localization | Easy | Translate UI strings into your language (see `Resources/*.lproj`) |
| Fix a UI bug | Easy-Medium | Check open issues labeled `bug` and `good first issue` |
| Add a test | Medium | Increase test coverage in `Tests/` |
| Improve onboarding | Medium | Enhance `OnboardingView.swift` with better UX |
| Add a new LLM provider | Medium-Hard | Implement a new `LLMService` in `Core/` |
| Accessibility improvements | Hard | Deep dive into `AXUIElement` APIs for better text replacement |

## Reporting Bugs

Use the [bug report template](https://github.com/thousandflowers/Parrot/issues/new?template=bug_report.md). Include:
- macOS version and CPU type (Apple Silicon / Intel)
- Parrot version
- Which LLM service you're using (Local / Ollama / OpenAI / OpenRouter)
- Steps to reproduce
- Console.app logs (filter: `com.thousandflowers.parrot`)

## Questions?

Start a [Discussion](https://github.com/thousandflowers/Parrot/discussions) for questions, ideas, or show-and-tell.
