import Carbon
import Cocoa

struct ShortcutConfig: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32  // Carbon modifiers (cmdKey, shiftKey, etc.)

    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(cmdKey)     != 0 { parts.append("⌘") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey)   != 0 { parts.append("⇧") }
        parts.append(Self.keyCodeToString(keyCode))
        return parts.joined()
    }

    static func keyCodeToString(_ kc: UInt32) -> String {
        let map: [UInt32: String] = [
            UInt32(kVK_ANSI_A):"A", UInt32(kVK_ANSI_B):"B", UInt32(kVK_ANSI_C):"C",
            UInt32(kVK_ANSI_D):"D", UInt32(kVK_ANSI_E):"E", UInt32(kVK_ANSI_F):"F",
            UInt32(kVK_ANSI_G):"G", UInt32(kVK_ANSI_H):"H", UInt32(kVK_ANSI_I):"I",
            UInt32(kVK_ANSI_J):"J", UInt32(kVK_ANSI_K):"K", UInt32(kVK_ANSI_L):"L",
            UInt32(kVK_ANSI_M):"M", UInt32(kVK_ANSI_N):"N", UInt32(kVK_ANSI_O):"O",
            UInt32(kVK_ANSI_P):"P", UInt32(kVK_ANSI_Q):"Q", UInt32(kVK_ANSI_R):"R",
            UInt32(kVK_ANSI_S):"S", UInt32(kVK_ANSI_T):"T", UInt32(kVK_ANSI_U):"U",
            UInt32(kVK_ANSI_V):"V", UInt32(kVK_ANSI_W):"W", UInt32(kVK_ANSI_X):"X",
            UInt32(kVK_ANSI_Y):"Y", UInt32(kVK_ANSI_Z):"Z",
            UInt32(kVK_ANSI_0):"0", UInt32(kVK_ANSI_1):"1", UInt32(kVK_ANSI_2):"2",
            UInt32(kVK_ANSI_3):"3", UInt32(kVK_ANSI_4):"4", UInt32(kVK_ANSI_5):"5",
            UInt32(kVK_ANSI_6):"6", UInt32(kVK_ANSI_7):"7", UInt32(kVK_ANSI_8):"8",
            UInt32(kVK_ANSI_9):"9",
            UInt32(kVK_Space):"Space", UInt32(kVK_Return):"↩",
            UInt32(kVK_Delete):"⌫",  UInt32(kVK_Escape):"⎋",
            UInt32(kVK_Tab):"⇥",
            UInt32(kVK_F1):"F1", UInt32(kVK_F2):"F2", UInt32(kVK_F3):"F3",
            UInt32(kVK_F4):"F4", UInt32(kVK_F5):"F5", UInt32(kVK_F6):"F6",
        ]
        return map[kc] ?? "Key\(kc)"
    }

    static func fromNSEvent(_ event: NSEvent) -> ShortcutConfig? {
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        guard !flags.isEmpty else { return nil }
        guard event.keyCode != UInt16(kVK_Escape) else { return nil }
        var mods: UInt32 = 0
        if event.modifierFlags.contains(.command) { mods |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.shift)   { mods |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.option)  { mods |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { mods |= UInt32(controlKey) }
        return ShortcutConfig(keyCode: UInt32(event.keyCode), modifiers: mods)
    }

    static let grammarDefault = ShortcutConfig(keyCode: UInt32(kVK_ANSI_E), modifiers: UInt32(cmdKey | shiftKey))
    static let fluencyDefault = ShortcutConfig(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | shiftKey))
    static let editorDefault  = ShortcutConfig(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(cmdKey | shiftKey))
    static let replaceDefault = ShortcutConfig(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(cmdKey | shiftKey))
    static let translateDefault = ShortcutConfig(keyCode: UInt32(kVK_ANSI_Y), modifiers: UInt32(cmdKey | shiftKey))
    static let applyDirectDefault = ShortcutConfig(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey | shiftKey))
    static let coachDefault    = ShortcutConfig(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | shiftKey))
    static let applyAllDefault = ShortcutConfig(keyCode: UInt32(kVK_ANSI_U), modifiers: UInt32(cmdKey | shiftKey))
}
