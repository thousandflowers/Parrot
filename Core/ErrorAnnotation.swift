import AppKit

enum ErrorSeverity: Sendable {
    case error    // replacement (wrong word → corrected word)
    case warning  // pure deletion (word removed)

    var nsColor: NSColor {
        switch self {
        case .error:   return .refineError
        case .warning: return .refineWarning
        }
    }
}

struct ErrorAnnotation: Identifiable, Sendable {
    let id: UUID
    let charRange: CFRange
    let originalSnippet: String
    let suggestedFix: String
    let severity: ErrorSeverity
}
