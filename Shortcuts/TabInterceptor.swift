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
            | (1 << CGEventType.leftMouseDown.rawValue)
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
    // A mouse click can reposition the caret in ways we cannot track → invalidate the typed buffer
    // and drop any visible suggestion. Never swallow the click.
    if type == .leftMouseDown {
        Task { @MainActor in
            CompletionController.shared.typedBuffer.invalidate()
            CompletionController.shared.dismiss()
        }
        return Unmanaged.passUnretained(event)
    }
    // Feed every keydown into the typed-input buffer (local, in-memory) so AX-blind apps still get a
    // reconstructed context. Runs for ALL keydowns, before the suggestion-visible gate below.
    if type == .keyDown { feedTypedBuffer(event) }
    guard type == .keyDown, TabInterceptor.isSuggestionVisible() else {
        return Unmanaged.passUnretained(event)
    }
    let keycode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    // Tab (no modifier) = accept the NEXT WORD (partial), then re-suggest. Whole-sentence accept is
    // on "\" below. (Per user spec: Tab = word, backslash = full.)
    let hasModifier = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) || flags.contains(.maskShift)
    if keycode == kVKTab && !hasModifier {
        Logger.infra.debug("TabInterceptor: Tab partial (word) accept")
        Task { @MainActor in
            if !CompletionController.shared.tryAcceptPartial() {
                // Suggestion was already cleared → let a real Tab through instead of eating it.
                let src = CGEventSource(stateID: .hidSystemState)
                if let td = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVKTab), keyDown: true),
                   let tu = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVKTab), keyDown: false) {
                    td.post(tap: .cghidEventTap)
                    tu.post(tap: .cghidEventTap)
                }
            }
        }
        return nil   // swallow the Tab
    }
    // "\" = accept the FULL suggestion. Detected by the produced CHARACTER, not keycode 42 — on the
    // Italian layout "\" is Option+Shift+/ (different keycode + modifiers), so a keycode check missed
    // it entirely. Only reached while a suggestion is visible (gate above). If the accept loses a
    // race (no current suggestion), re-post the SAME key event so the user's "\" is not eaten.
    if event.typedCharacter() == "\\" {
        Logger.infra.debug("TabInterceptor: backslash full accept")
        let kc = CGKeyCode(keycode)
        let fl = flags
        Task { @MainActor in
            if !CompletionController.shared.tryAcceptFull() {
                let src = CGEventSource(stateID: .hidSystemState)
                if let bd = CGEvent(keyboardEventSource: src, virtualKey: kc, keyDown: true),
                   let bu = CGEvent(keyboardEventSource: src, virtualKey: kc, keyDown: false) {
                    bd.flags = fl; bu.flags = fl
                    bd.post(tap: .cghidEventTap)
                    bu.post(tap: .cghidEventTap)
                }
            }
        }
        return nil   // swallow the backslash
    }
    // ⌘→ accepts a single word (partial accept), then re-suggests.
    if keycode == kVKRightArrow && flags.contains(.maskCommand) {
        Logger.infra.debug("TabInterceptor: ⌘→ partial accept")
        Task { @MainActor in
            if !CompletionController.shared.tryAcceptPartial() {
                let src = CGEventSource(stateID: .hidSystemState)
                let kVKRight: CGKeyCode = 124
                if let rd = CGEvent(keyboardEventSource: src, virtualKey: kVKRight, keyDown: true),
                   let ru = CGEvent(keyboardEventSource: src, virtualKey: kVKRight, keyDown: false) {
                    rd.flags = .maskCommand
                    ru.flags = .maskCommand
                    rd.post(tap: .cghidEventTap)
                    ru.post(tap: .cghidEventTap)
                }
            }
        }
        return nil
    }
    if keycode == kVKEscape {
        // Only dismiss if a suggestion is actually visible — otherwise let
        // Escape reach the app (e.g. Xcode code-completion, close popover).
        Task { @MainActor in CompletionController.shared.dismiss() }
        return Unmanaged.passUnretained(event)   // let Escape through
    }
    // Any other key dismisses the stale suggestion but is not swallowed.
    Task { @MainActor in CompletionController.shared.dismissForTyping(keycode: keycode) }
    return Unmanaged.passUnretained(event)
}

private let kVKBackspace: Int64 = 51

/// Updates the in-memory typed-input buffer from a keydown so AX-blind apps still have a context to
/// complete from. Reconstruction is best-effort: any caret-moving or text-mutating chord
/// (⌘V/⌘Z/⌘A/⌘←, arrows) invalidates the buffer so we never complete on a stale reconstruction.
private func feedTypedBuffer(_ event: CGEvent) {
    let keycode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    #if DEBUG
    CrashLogger.log("DIAG buf: keycode=\(keycode) char=\(event.typedCharacter().map { String($0) } ?? "nil") cmd=\(flags.contains(.maskCommand)) ctrl=\(flags.contains(.maskControl))")
    #endif
    if flags.contains(.maskCommand) || flags.contains(.maskControl) {
        Task { @MainActor in CompletionController.shared.typedBuffer.invalidate() }
        return
    }
    switch keycode {
    case 123, 124, 125, 126:                 // arrow keys → caret moved, can't track
        Task { @MainActor in CompletionController.shared.typedBuffer.invalidate() }
    case kVKBackspace:                        // backspace
        Task { @MainActor in CompletionController.shared.typedBuffer.deleteBackward() }
    case kVKTab, kVKEscape:                    // not text
        break
    default:
        guard let ch = event.typedCharacter() else { return }
        Task { @MainActor in CompletionController.shared.typedBuffer.type(character: ch) }
    }
}

private extension CGEvent {
    /// The Unicode character this keydown would produce, or nil for non-printing keys / newlines.
    func typedCharacter() -> Character? {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: length)
        guard let c = s.first, !c.isNewline else { return nil }
        return c
    }
}
