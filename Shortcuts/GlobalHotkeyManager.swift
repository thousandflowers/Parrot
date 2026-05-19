import Cocoa
import Carbon

@MainActor
final class GlobalHotkeyManager {
    nonisolated(unsafe) private(set) static weak var current: GlobalHotkeyManager?

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private let actionsLock = NSLock()
    private var nextID: UInt32 = 1
    private(set) var failedShortcuts: [String] = []

    init() { Self.current = self }

    func registerHotkeys() {
        installEventHandlerIfNeeded()
        unregisterAll()
        registerFromPrefs()
    }

    func updateHotkeys() {
        unregisterAll()
        registerFromPrefs()
    }

    private func registerFromPrefs() {
        let prefs = PreferencesStore.shared
        failedShortcuts = []

        register(
            keyCode: prefs.shortcutGrammar.keyCode,
            modifiers: prefs.shortcutGrammar.modifiers,
            label: prefs.shortcutGrammar.displayString,
            action: { TextCheckCoordinator.shared.checkSelectedText() },
            enabled: prefs.shortcutGrammar.isEnabled
        )
        register(
            keyCode: prefs.shortcutFluency.keyCode,
            modifiers: prefs.shortcutFluency.modifiers,
            label: prefs.shortcutFluency.displayString,
            action: { TextCheckCoordinator.shared.checkFluency() },
            enabled: prefs.shortcutFluency.isEnabled
        )
        register(
            keyCode: prefs.shortcutEditor.keyCode,
            modifiers: prefs.shortcutEditor.modifiers,
            label: prefs.shortcutEditor.displayString,
            action: { Task { await TextCheckCoordinator.shared.openFloatingEditor() } },
            enabled: prefs.shortcutEditor.isEnabled
        )
        register(
            keyCode: prefs.shortcutReplace.keyCode,
            modifiers: prefs.shortcutReplace.modifiers,
            label: prefs.shortcutReplace.displayString,
            action: { TextCheckCoordinator.shared.checkAndReplace() },
            enabled: prefs.shortcutReplace.isEnabled
        )
        register(
            keyCode: prefs.shortcutTranslate.keyCode,
            modifiers: prefs.shortcutTranslate.modifiers,
            label: prefs.shortcutTranslate.displayString,
            action: { TextCheckCoordinator.shared.checkTranslation() },
            enabled: prefs.shortcutTranslate.isEnabled
        )
        register(
            keyCode: prefs.shortcutApplyDirect.keyCode,
            modifiers: prefs.shortcutApplyDirect.modifiers,
            label: prefs.shortcutApplyDirect.displayString,
            action: { TextCheckCoordinator.shared.checkAndApplyDirect() },
            enabled: prefs.shortcutApplyDirect.isEnabled
        )
        register(
            keyCode: prefs.shortcutCoach.keyCode,
            modifiers: prefs.shortcutCoach.modifiers,
            label: prefs.shortcutCoach.displayString,
            action: { TextCheckCoordinator.shared.checkCoach() },
            enabled: prefs.shortcutCoach.isEnabled
        )
        register(
            keyCode: prefs.shortcutApplyAll.keyCode,
            modifiers: prefs.shortcutApplyAll.modifiers,
            label: prefs.shortcutApplyAll.displayString,
            action: { InlineHighlightController.shared.applyAllAnnotations() },
            enabled: prefs.shortcutApplyAll.isEnabled
        )
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

    private func unregisterAll() {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        actionsLock.lock()
        actions.removeAll()
        actionsLock.unlock()
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

    deinit {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        if let handler = eventHandler { RemoveEventHandler(handler) }
    }
}
