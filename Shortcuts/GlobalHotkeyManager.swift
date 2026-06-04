import Cocoa
import Carbon
import OSLog

@MainActor
final class GlobalHotkeyManager {
    nonisolated private static let _currentLock = OSAllocatedUnfairLock<WeakRef>(initialState: WeakRef())

    private struct WeakRef: @unchecked Sendable {
        weak var value: GlobalHotkeyManager?
    }

    static var current: GlobalHotkeyManager? {
        _currentLock.withLock { $0.value }
    }

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private let actionsLock = NSLock()
    private var nextID: UInt32 = 1
    private(set) var failedShortcuts: [String] = []

    init() { Self._currentLock.withLock { $0.value = self } }

    func registerHotkeys() {
        unregisterAll()
        installEventHandlerIfNeeded()
        registerFromPrefs()
    }

    func updateHotkeys() {
        unregisterAll()
        installEventHandlerIfNeeded()
        registerFromPrefs()
    }

    private func registerFromPrefs() {
        let prefs = PreferencesStore.shared
        failedShortcuts = []
        let entries: [(ShortcutConfig, () -> Void)] = [
            (prefs.shortcutGrammar,        { TextCheckCoordinator.shared.checkSelectedText() }),
            (prefs.shortcutFluency,        { TextCheckCoordinator.shared.checkFluency() }),
            (prefs.shortcutEditor,         { Task { await TextCheckCoordinator.shared.openFloatingEditor() } }),
            (prefs.shortcutReplace,        { TextCheckCoordinator.shared.checkAndReplace() }),
            (prefs.shortcutTranslate,      { TextCheckCoordinator.shared.checkTranslation() }),
            (prefs.shortcutApplyDirect,    { TextCheckCoordinator.shared.checkAndApplyDirect() }),
            (prefs.shortcutCoach,          { TextCheckCoordinator.shared.checkCoach() }),
            (prefs.shortcutApplyAll,       { InlineHighlightController.shared.applyAllAnnotations() }),
            (prefs.shortcutGrammarFluency, { TextCheckCoordinator.shared.checkGrammarThenFluency() }),
            (prefs.shortcutDeSlop,         { TextCheckCoordinator.shared.checkDeSlop() }),
            (prefs.shortcutAIPrompt,       { TextCheckCoordinator.shared.checkAIPrompt() }),
        ]
        for (config, action) in entries {
            register(keyCode: config.keyCode, modifiers: config.modifiers,
                     label: config.displayString, action: action, enabled: config.isEnabled)
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        let eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let callback: EventHandlerUPP = { _, eventRef, userData -> OSStatus in
            guard let eventRef, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let result = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil,
                &hotKeyID
            )
            guard result == noErr else { return noErr }
            let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.actionsLock.lock()
            let action = manager.actions[hotKeyID.id]
            manager.actionsLock.unlock()
            action?()
            return noErr
        }
        InstallEventHandler(GetEventDispatcherTarget(), callback, 1, [eventSpec], selfPtr, &eventHandler)
    }

    func unregisterAll() {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        actionsLock.lock()
        actions.removeAll()
        actionsLock.unlock()
        if let handler = eventHandler { RemoveEventHandler(handler); eventHandler = nil }
    }

    private func register(keyCode: UInt32, modifiers: UInt32, label: String, action: @escaping () -> Void, enabled: Bool = true) {
        guard enabled else { return }
        let id = EventHotKeyID(signature: OSType(0x5246434C), id: nextID)
        nextID += 1

        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, id,
            GetEventDispatcherTarget(), 0, &hotKeyRef
        )

        guard status == noErr, let ref = hotKeyRef else {
            failedShortcuts.append(label)
            return
        }

        hotKeyRefs.append(ref)
        actionsLock.lock()
        actions[id.id] = action
        actionsLock.unlock()
    }

    func shutdown() {
        unregisterAll()
    }

    deinit {
        // shutdown() should be called explicitly from AppDelegate.applicationWillTerminate
        // This deinit is a safety net for development/debugging scenarios
    }
}
