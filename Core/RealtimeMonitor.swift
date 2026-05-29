import Cocoa
@preconcurrency import CoreFoundation

actor RealtimeMonitor {
    static let shared = RealtimeMonitor()

    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var lastTextHash: Int?
    private var debounceTask: Task<Void, Never>?
    private var isEnabled = false

    func start() {
        guard !isEnabled else { return }
        isEnabled = true
        Task { await attachToFocusedApp() }
    }

    func stop() {
        isEnabled = false
        detachObserver()
        debounceTask?.cancel()
        debounceTask = nil
        lastTextHash = nil
    }

    func frontAppChanged() {
        lastTextHash = nil
        Task { await RealtimeIndicatorController.shared.hide() }
        Task { await attachToFocusedApp() }
        // Clear any inline-completion ghost left over from the previous app.
        Task { @MainActor in CompletionController.shared.dismiss() }
    }

    private func attachToFocusedApp() async {
        guard isEnabled else { return }
        guard AXIsProcessTrusted() else { return }

        let systemAX = AXUIElementCreateSystemWide()
        var frontAppRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemAX, kAXFocusedApplicationAttribute as CFString, &frontAppRef
        ) == .success,
        let frontApp = frontAppRef,
        let frontAppAX = AccessibilityBridge.asElementPublic(frontApp) else {
            return
        }

        var pid: pid_t = 0
        AXUIElementGetPid(frontAppAX, &pid)
        guard pid != 0 else { return }

        if pid == observedPID { return }

        detachObserver()

        var newObserver: AXObserver?
        guard AXObserverCreate(pid, axNotificationCallback, &newObserver) == .success,
              let obs = newObserver else {
            return
        }

        let notifications: [String] = [
            "AXValueChanged",
            "AXFocusedUIElementChanged",
            "AXSelectedTextChanged"
        ]

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        for notif in notifications {
            AXObserverAddNotification(obs, frontAppAX, notif as CFString, selfPtr)
        }

        // CFRunLoop ops must run on the run loop's own thread (main thread).
        let runLoopSource = AXObserverGetRunLoopSource(obs)
        await MainActor.run {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }

        self.observer = obs
        self.observedPID = pid
        lastTextHash = nil
    }

    private func detachObserver() {
        guard let obs = observer else { return }
        let runLoopSource = AXObserverGetRunLoopSource(obs)
        // CFRunLoop ops must run on the run loop's own thread (main thread).
        DispatchQueue.main.async {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        observer = nil
        observedPID = 0
    }

    nonisolated func handleNotification() {
        Task { await Self.shared.onAccessibilityEvent() }
        // Inline completion runs independently of realtime correction (different feature/toggle).
        Task { @MainActor in CompletionController.shared.textChanged() }
    }

    private func onAccessibilityEvent() async {
        guard isEnabled else { return }
        guard UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.realtimeEnabled) else { return }

        let pid = await AccessibilityBridge.shared.lastKnownFrontAppPID()
        guard pid != 0 else { return }

        let bundleID = await AppDetector.shared.frontAppBundleID(forPID: pid)
        if let id = bundleID {
            let excluded = await MainActor.run { PreferencesStore.shared.isExcluded(bundleID: id) }
            if excluded { return }
        }

        guard let text = try? await fetchCurrentText(pid: pid), !text.isEmpty else { return }

        let hash = text.hashValue
        guard hash != lastTextHash else { return }
        lastTextHash = hash

        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            let bundleID = await AppDetector.shared.frontAppBundleID(forPID: pid)
            let (promptType, overrideService, overridePrompt) = await resolvePromptInfo(for: bundleID)
            await performCheck(text: text, promptType: promptType, overrideServiceType: overrideService, overrideCustomPrompt: overridePrompt)
        }
    }

    private func fetchCurrentText(pid: pid_t) async throws -> String {
        do {
            return try await AccessibilityBridge.shared.fetchSelectedText(fromPID: pid)
        } catch CorrectionError.noTextSelected {
            let (text, _) = try await AccessibilityBridge.shared.fetchTextOrLineAtCursor(fromPID: pid)
            return text
        }
    }

    private func performCheck(text: String, promptType: PromptType, overrideServiceType: ServiceType?, overrideCustomPrompt: CustomPrompt?) async {
        guard !text.isEmpty else { return }

        do {
            let userLanguage = await MainActor.run { PreferencesStore.shared.language }
            let result = try await RequestQueue.shared.enqueue(
                text: text,
                type: promptType,
                priority: .autoCheck,
                overrideServiceType: overrideServiceType,
                overrideCustomPrompt: overrideCustomPrompt,
                language: userLanguage
            )
            if result.originalText != result.correctedText {
                await RealtimeIndicatorController.shared.show(errors: true)
            } else {
                await RealtimeIndicatorController.shared.show(errors: false)
            }
        } catch {
            await RealtimeIndicatorController.shared.hide()
        }
    }

    private func resolvePromptInfo(for bundleID: String?) async -> (PromptType, ServiceType?, CustomPrompt?) {
        guard let bundleID else { return (.grammar, nil, nil) }
        let rules = await MainActor.run { PreferencesStore.shared.appRules }
        guard let rule = rules.first(where: { $0.bundleID == bundleID && $0.isEnabled }) else { return (.grammar, nil, nil) }

        let customPrompt: CustomPrompt? = if let promptID = rule.promptID {
            await MainActor.run { PreferencesStore.shared.customPrompts.first(where: { $0.id == promptID }) }
        } else { nil }

        let promptType: PromptType = if let prompt = customPrompt {
            .custom(name: prompt.name, template: prompt.template)
        } else {
            .grammar
        }

        return (promptType, rule.serviceType, customPrompt)
    }
}

private func axNotificationCallback(observer: AXObserver, element: AXUIElement, notificationName: CFString, userInfo: UnsafeMutableRawPointer?) {
    guard let userInfo else { return }
    let monitor = Unmanaged<RealtimeMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    monitor.handleNotification()
}
