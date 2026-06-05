import Cocoa
import os
import SwiftUI
import ObjectiveC
import IOKit.hid

class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyManager: GlobalHotkeyManager?
    private var frontAppObserver: NSObjectProtocol?

    // MARK: - Custom Menu Bar Popover
    private var popover: NSPanel?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashLogger.install()
        installReportExceptionSwizzle()
        CrashLogger.log("launch: start")

        NSApp.setActivationPolicy(.accessory)
        CrashLogger.log("launch: activation policy set")

        // --- START WARMUP IMMEDIATELY (before UI setup) ---
        // The local server takes 5-15s to load a GGUF model into RAM on first launch.
        // A detached high-priority Task starts immediately without waiting for the
        // main actor's cooperative pool, so the server can be ready before the user
        // starts typing. Wren mode always needs the server for LlamaCompletionClient fallback.
        let mode = AppMode.current
        let serviceType = LLMServiceFactory.resolveDefaultServiceType()
        let warmupNeeded: Bool
        if mode.showsCorrection && serviceType == .local {
            warmupNeeded = true
        } else if mode.showsCompletion && PreferencesStore.shared.inlineCompletionEnabled {
            // Always warm up the main server in Wren mode. Even when a dedicated completion
            // model is set, the main server serves as fallback if the dedicated one fails
            // (model not local, RAM pressure, etc.). Without this warmup, resolvedTarget()
            // falls back to mainTarget() which finds currentPort=0 → no suggestions at all.
            warmupNeeded = true
        } else {
            warmupNeeded = false
        }
        if warmupNeeded {
            Task(priority: .userInitiated) {
                await MainActor.run { MenuBarParrot.shared.setState(.sleeping) }
                await LocalLLMService.shared.warmup()
                await MainActor.run { MenuBarParrot.shared.setState(.idle) }
            }
        } else if serviceType == .appleIntelligence {
            if #available(macOS 26.0, *) {
                Task {
                    if !AppleIntelligenceService.shared.isAvailable {
                        os.Logger.infra.info("Apple Intelligence not available: \(AppleIntelligenceService.shared.availabilityDescription)")
                    }
                }
            }
        }

        // Wren needs an on-device model to generate suggestions. We warm up above, but if NO model is
        // installed completion can never produce anything — surface that once (with a path to fix it)
        // instead of failing silently, which reads as "the app is broken".
        if mode.showsCompletion && PreferencesStore.shared.inlineCompletionEnabled {
            Task {
                guard (await ModelManager.shared.localModels()).isEmpty else { return }
                await MainActor.run {
                    let ackKey = "hasAcknowledgedNoCompletionModel"
                    guard !UserDefaults.standard.bool(forKey: ackKey) else { return }
                    let alert = NSAlert()
                    alert.messageText = String(localized: "alert.completion.no_model.title",
                                               defaultValue: "Nessun modello installato")
                    alert.informativeText = String(localized: "alert.completion.no_model.body",
                                                   defaultValue: "Wren genera i suggerimenti con un modello on-device. Scarica un modello nelle Impostazioni per attivare il completamento inline.")
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: String(localized: "alert.completion.no_model.open_settings",
                                                      defaultValue: "Apri Impostazioni"))
                    alert.addButton(withTitle: String(localized: "alert.ok", defaultValue: "OK"))
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } else {
                        UserDefaults.standard.set(true, forKey: ackKey)
                    }
                }
            }
        }
        // --------------------------------------------------

        setupStatusItem()
        CrashLogger.log("launch: status item ready")

        setupPopover()
        CrashLogger.log("launch: popover ready")

        checkAccessibilityPermissions()
        CrashLogger.log("launch: accessibility checked")

        hotkeyManager = GlobalHotkeyManager()
        hotkeyManager?.registerHotkeys()
        CrashLogger.log("launch: hotkeys registered")

        warnFailedShortcuts()

        observeFrontmostAppChanges()
        CrashLogger.log("launch: observers set")

        OnboardingController.shared.showIfNeeded()
        ToneTuneUpPresenter.presentIfDue()
        CrashLogger.log("launch: onboarding checked")

        // Load correction cache persisted from previous session
        Task { await CorrectionCache.shared.loadFromDisk() }

        let realtimeOn = mode.showsCorrection && UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.realtimeEnabled)
        let completionOn = mode.showsCompletion && PreferencesStore.shared.inlineCompletionEnabled
        if realtimeOn || completionOn {
            Task { await RealtimeMonitor.shared.start() }
        }
        if completionOn {
            TabInterceptor.shared.start()
            // Warm the completion model into RAM now so the first keystroke doesn't trigger a
            // multi-second cold load (during which fast typing supersedes every request → nothing).
            Task(priority: .utility) { await CompletionEngine.shared.warmup() }
            // Screen context (optional): prompt once for Screen Recording so Wren can read the
            // conversation above the caret. No-ops / degrades to text-field-only if denied.
            if PreferencesStore.shared.completionScreenContextEnabled, !ScreenContextProvider.hasPermission {
                ScreenContextProvider.requestPermission()
            }
        }
        CrashLogger.log("DIAG completion: mode=\(mode.displayName) completionOn=\(completionOn) axTrusted=\(AXIsProcessTrusted()) inputMon=\(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue)")

        CrashLogger.log("launch: serviceType=\(serviceType.rawValue)")
        CrashLogger.log("launch: complete")
    }

    // MARK: - Custom Menu Bar Popover

    @MainActor
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        let appName = AppMode.current.displayName
        button.setAccessibilityLabel("\(appName) menu")
        button.setAccessibilityHelp(AppMode.current.showsCompletion
            ? "Open the \(appName) completion menu"
            : "Open the \(appName) correction menu")
        MenuBarParrot.shared.attach(to: button, statusItem: statusItem!)
    }

    private func setupPopover() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 480),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.delegate = self

        panel.minSize = NSSize(width: 280, height: 400)
        panel.maxSize = NSSize(width: 480, height: 800)

        let hostingView = NSHostingView(rootView: MenuBarView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 14.0, *) {
            hostingView.sizingOptions = [.intrinsicContentSize]
        }
        panel.contentView?.addSubview(hostingView)

        if let contentView = panel.contentView {
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
                hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }

        self.popover = panel
    }

    @objc private func togglePopover() {
        guard let panel = popover else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            positionPopoverBelowStatusItem()
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            animatePopoverIn()
        }
    }

    private func animatePopoverIn() {
        guard let panel = popover, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let targetOrigin = panel.frame.origin
        var slideOrigin = targetOrigin
        slideOrigin.y += 8
        panel.setFrameOrigin(slideOrigin)
        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
            panel.animator().setFrameOrigin(targetOrigin)
        }
    }

    private func positionPopoverBelowStatusItem() {
        guard let panel = popover, let button = statusItem?.button, let buttonWindow = button.window else { return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
        let panelSize = panel.frame.size

        let x = screenRect.midX - panelSize.width / 2
        let y = screenRect.minY - panelSize.height - 5

        if let screen = buttonWindow.screen {
            let screenFrame = screen.visibleFrame
            let clampedX = max(screenFrame.minX + 4, min(x, screenFrame.maxX - panelSize.width - 4))
            let clampedY = max(screenFrame.minY + 4, y)
            panel.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
        } else {
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    // MARK: - Application Lifecycle

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let replySent = OSAllocatedUnfairLock<Bool>(initialState: false)
        let replyOnce: @Sendable () -> Void = {
            let alreadySent = replySent.withLock { state in
                let prev = state
                state = true
                return prev
            }
            guard !alreadySent else { return }
            Task { @MainActor in
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(10))
            replyOnce()
        }
        Task {
            await RealtimeMonitor.shared.stop()
            await ServerManager.shared.stop()
            await ServerHealthMonitor.shared.stopMonitoring()
            timeoutTask.cancel()
            replyOnce()
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func application(_ app: NSApplication, open urls: [URL]) {
        for url in urls {
            handleDeepLink(url)
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "parrot", url.host == "correct" else { return }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems,
           let encoded = queryItems.first(where: { $0.name == "text" })?.value,
           let decoded = encoded.removingPercentEncoding,
           !decoded.isEmpty {
            let mode = queryItems.first(where: { $0.name == "mode" })?.value
            let promptType: PromptType
            switch mode {
            case "fluency": promptType = .fluency
            case "translate": promptType = .translation(targetLanguage: "en")
            default: promptType = .grammar
            }
            Task { @MainActor in
                TextCheckCoordinator.shared.correctText(decoded, mode: promptType)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        InlineHighlightController.shared.clear()
        hotkeyManager?.shutdown()
        if let observer = frontAppObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            frontAppObserver = nil
        }
        PreferencesStore.shared.cleanup()
    }

    // MARK: - Accessibility

    private func checkAccessibilityPermissions() {
        guard shouldShowAccessibilityWarning() else { return }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let enabled = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if !enabled {
            let alert = NSAlert()
            alert.messageText = String(localized: "alert.accessibility.title")
            alert.informativeText = String(localized: "alert.accessibility.body")
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "alert.accessibility.open_settings"))
            alert.addButton(withTitle: String(localized: "alert.accessibility.ignore"))
            alert.addButton(withTitle: String(localized: "alert.ok"))
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            } else if response == .alertSecondButtonReturn {
                UserDefaults.standard.set(true, forKey: "hasAcknowledgedAccessibilityWarning")
            }
        }
    }

    private func shouldShowAccessibilityWarning() -> Bool {
        if AXIsProcessTrusted() { return false }
        if UserDefaults.standard.bool(forKey: "hasAcknowledgedAccessibilityWarning") { return false }
        return true
    }

    private func observeFrontmostAppChanges() {
        // Seed the cache with the app already frontmost at launch. The observer below only updates on
        // SUBSEQUENT activations, so without this seed the cached pid stays 0 until the user's first
        // app switch — and completion/correction (both read this pid) silently do nothing until then.
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            let seedPID = front.processIdentifier
            Task { await AccessibilityBridge.shared.setLastKnownFrontAppPID(seedPID) }
        }
        frontAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            Task {
                await AccessibilityBridge.shared.setLastKnownFrontAppPID(app.processIdentifier)
                await RealtimeMonitor.shared.frontAppChanged()
            }
        }
    }

    @MainActor
    private func warnFailedShortcuts() {
        guard let failed = hotkeyManager?.failedShortcuts, !failed.isEmpty else { return }
        let list = failed.joined(separator: ", ")
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.shortcuts.title")
        alert.informativeText = String(format: String(localized: "alert.shortcuts.body_format"), list)
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "alert.ok"))
        alert.runModal()
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSPanel == popover else { return }
        popover?.orderOut(nil)
    }
}

// MARK: - Exception logging swizzle

private func installReportExceptionSwizzle() {
    // Swizzle the CLASS method +[NSApplication _crashOnException:] to capture
    // the NSException name/reason before AppKit raises SIGTRAP.
    guard let cls = NSClassFromString("NSApplication") else { return }
    let crashSel = NSSelectorFromString("_crashOnException:")
    let replaceSel = NSSelectorFromString("_parrot_crashOnException:")

    guard
        let original = class_getClassMethod(cls, crashSel),
        let replacement = class_getClassMethod(AppDelegate.self, replaceSel)
    else {
        CrashLogger.log("swizzle: _crashOnException: method not found")
        return
    }
    method_exchangeImplementations(original, replacement)
    CrashLogger.log("swizzle: _crashOnException: installed")
}

extension AppDelegate {
    // Replacement for +[NSApplication _crashOnException:]
    @objc class func _parrot_crashOnException(_ exception: NSException) {
        // macOS 26+: NSHostingView calls setNeedsUpdateConstraints during updateConstraints,
        // triggering AppKit's re-entrant constraint loop guard. This is a SwiftUI/AppKit
        // interaction bug — layout recovers on the next display cycle, so swallow it.
        if exception.name == .genericException,
           let reason = exception.reason,
           reason.contains("Update Constraints in Window pass") {
            CrashLogger.log("constraint-loop swallowed (macOS 26 compat): \(reason.prefix(120))")
            return
        }
        CrashLogger.writeCrash(
            title: "NSException → _crashOnException",
            detail: """
            Name: \(exception.name.rawValue)
            Reason: \(exception.reason ?? "nil")
            UserInfo: \(exception.userInfo?.description ?? "nil")
            Stack:
            \(exception.callStackSymbols.joined(separator: "\n"))
            """
        )
        // Call the (now-swapped) original implementation
        AppDelegate._parrot_crashOnException(exception)
    }
}
