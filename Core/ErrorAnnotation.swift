import AppKit

enum ErrorSeverity: Sendable {
    case error    // replacement (wrong word → corrected word)
    case warning  // pure deletion (word removed)

    var nsColor: NSColor {
        switch self {
        case .error:   return NSColor.diffDeletion
        case .warning: return NSColor.statusWarning
        }
    }
}

struct ErrorAnnotation: Identifiable, Sendable {
    let id: UUID
    let charRange: CFRange
    let originalSnippet: String
    var suggestedFix: String
    var severity: ErrorSeverity
}
