import Cocoa
import Carbon

/// Manages global keyboard shortcuts via Carbon Event Manager.
/// Delegates business logic to TextCheckCoordinator.
@MainActor
final class GlobalHotkeyManager {
    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1

    func registerHotkeys() {
        let eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Singleton lifetime: never use takeRetainedValue() here (causes EXC_BAD_ACCESS on 2nd press)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let callback: EventHandlerUPP = { _, eventRef, userData -> OSStatus in
            guard let eventRef = eventRef, let userData = userData else { return noErr }

            var hotKeyID = EventHotKeyID()
            let result = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard result == noErr else { return noErr }

            let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.actions[hotKeyID.id]?()
            return noErr
        }

        InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            1,
            [eventSpec],
            selfPtr,
            &eventHandler
        )

        register(
            keyCode: UInt32(kVK_ANSI_E),
            modifiers: UInt32(cmdKey | shiftKey),
            action: { TextCheckCoordinator.shared.checkSelectedText() }
        )

        register(
            keyCode: UInt32(kVK_ANSI_T),
            modifiers: UInt32(cmdKey | shiftKey),
            action: { TextCheckCoordinator.shared.checkFluency() }
        )

        register(
            keyCode: UInt32(kVK_ANSI_F),
            modifiers: UInt32(cmdKey | shiftKey),
            action: { Task { await TextCheckCoordinator.shared.openFloatingEditor() } }
        )
    }

    private func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        let id = EventHotKeyID(signature: OSType(0x5246434C), id: nextID)
        nextID += 1

        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            id,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let ref = hotKeyRef else { return }

        hotKeyRefs.append(ref)
        actions[id.id] = action
    }

    deinit {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }
}

extension Notification.Name {
    static let checkTextEmptyNotification = Notification.Name("checkTextEmptyNotification")
    static let checkTextErrorNotification = Notification.Name("checkTextErrorNotification")
}
