import Foundation

/// Reports how well Wren's inline completion works in the focused app, by observing what the
/// Accessibility read actually returns — never by matching the bundle id. Used to build the
/// "Works in" compatibility matrix and to give users a self-service capability check.
///
/// Classification is derived from a single real AX read (`AccessibilityBridge.completionContext`,
/// which already forces `AXManualAccessibility` for Chromium/Electron apps):
///   - `.full`        — the field's text around the caret is readable → context-aware completion.
///   - `.typedOnly`   — nothing readable → Wren falls back to the typed-input buffer; it still
///                       completes from what you type in this session, but cannot see pre-existing
///                       text in the field.
///   - `.secureField` — a password field; Wren deliberately never completes here.
///   - `.noFocus`     — no editable field focused right now (inconclusive; try again while typing).
enum AppCompatibility: String, Sendable {
    case full
    case typedOnly
    case secureField
    case noFocus

    /// Human-readable verdict for the README matrix.
    var verdict: String {
        switch self {
        case .full:        return "✅ Full"
        case .typedOnly:   return "⚠️ Partial (typed-only)"
        case .secureField: return "🔒 Secure field (by design)"
        case .noFocus:     return "— No field focused"
        }
    }
}

enum CompatibilityProbe {
    /// Pure classifier: maps an AX read result to a compatibility verdict.
    /// `focused` distinguishes "no editable field" from "field present but unreadable".
    static func classify(context: CompletionAXContext?, focused: Bool) -> AppCompatibility {
        guard let ctx = context else {
            return focused ? .typedOnly : .noFocus
        }
        if ctx.isSecure { return .secureField }
        // A readable field with usable text around the caret = full context completion.
        if ctx.preContext.isEmpty && ctx.postContext.isEmpty {
            // Field is readable but empty — still "full": Wren can read it, just nothing there yet.
            return .full
        }
        return .full
    }

    /// Probes the focused app via the real AX read. `contextProvider` returns the AX context (or nil),
    /// `hasFocusedField` reports whether an editable element is focused at all.
    static func probe(
        pid: pid_t,
        contextProvider: (pid_t) async -> CompletionAXContext?,
        hasFocusedField: (pid_t) async -> Bool
    ) async -> AppCompatibility {
        let ctx = await contextProvider(pid)
        let focused = ctx != nil ? true : await hasFocusedField(pid)
        return classify(context: ctx, focused: focused)
    }
}
