import AppKit
import os
import IOKit.hid

/// Global keyboard tap that accepts an inline suggestion with Tab. SAFETY: the tap swallows a key
/// ONLY when a suggestion is currently visible AND the key is Tab; in every other case it passes
/// the event through untouched. The visibility flag is read from a lock so the C tap callback
/// (which runs off the main thread) never touches main-actor state directly.
@MainActor
final class TabInterceptor {
    static let shared = TabInterceptor()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Read by the tap callback on its own thread — must be reachable from a nonisolated context.
    nonisolated private static let visible = OSAllocatedUnfairLock<Bool>(initialState: false)
    nonisolated static func setSuggestionVisible(_ v: Bool) { visible.withLock { $0 = v } }
    nonisolated static func isSuggestionVisible() -> Bool { visible.withLock { $0 } }

    // The active tap, so the callback can re-enable it after a system timeout.
    nonisolated fileprivate static let activeTap = OSAllocatedUnfairLock<CFMachPort?>(initialState: nil)

    private init() {}

    func start() {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else {
            Logger.infra.error("TabInterceptor: not starting — Accessibility not trusted")
            return
        }
        // A keyboard CGEventTap that SWALLOWS keys needs Input Monitoring (kIOHIDRequestTypeListenEvent),
        // not just Accessibility. Without it the tap is created but receives no key events — Tab passes
        // through as a literal tab. Request it so macOS adds Parrot to the Input Monitoring list / prompts.
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        Logger.infra.info("TabInterceptor: input-monitoring access=\(access.rawValue) (0=granted,1=denied,2=unknown)")
        if access != kIOHIDAccessTypeGranted {
            let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            Logger.infra.info("TabInterceptor: requested input monitoring, granted=\(granted)")
        }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.tapDisabledByTimeout.rawValue)
            | (1 << CGEventType.tapDisabledByUserInput.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                        options: .defaultTap, eventsOfInterest: mask,
                                        callback: tabTapCallback, userInfo: nil) else {
            Logger.infra.error("TabInterceptor: CGEvent.tapCreate returned nil")
            return
        }
        Logger.infra.info("TabInterceptor: keyboard tap installed")
        tap = t
        Self.activeTap.withLock { $0 = t }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        Self.activeTap.withLock { $0 = nil }
        tap = nil
        runLoopSource = nil
        Self.setSuggestionVisible(false)
    }
}

private let kVKTab: Int64 = 48
private let kVKEscape: Int64 = 53
private let kVKRightArrow: Int64 = 124   // ⌘→ = accept one word (partial)

/// C-compatible tap callback. Must not capture context. Keeps work minimal; UI calls are bounced
/// to the main actor. Returns nil only to swallow Tab while a suggestion is shown.
private func tabTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                            userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = TabInterceptor.activeTap.withLock({ $0 }) { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown, TabInterceptor.isSuggestionVisible() else {
        return Unmanaged.passUnretained(event)
    }
    let keycode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    // Ignore Tab combined with modifiers (e.g. ⌘Tab app switch) — only plain Tab accepts.
    let hasModifier = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
    if keycode == kVKTab && !hasModifier {
        Logger.infra.debug("TabInterceptor: Tab accepted suggestion")
        Task { @MainActor in CompletionController.shared.acceptFull() }
        return nil   // swallow the Tab
    }
    // ⌘→ accepts a single word (partial accept), then re-suggests.
    if keycode == kVKRightArrow && flags.contains(.maskCommand) {
        Logger.infra.debug("TabInterceptor: ⌘→ partial accept")
        Task { @MainActor in CompletionController.shared.acceptPartial() }
        return nil
    }
    if keycode == kVKEscape {
        Task { @MainActor in CompletionController.shared.dismiss() }
        return Unmanaged.passUnretained(event)   // let Escape through
    }
    // Any other key dismisses the stale suggestion but is not swallowed.
    Task { @MainActor in CompletionController.shared.dismiss() }
    return Unmanaged.passUnretained(event)
}
