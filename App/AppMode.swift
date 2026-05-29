import Foundation

/// Parrot and Wren ship from one codebase as two separate apps (distinct bundles, icons,
/// identities, and permissions). The mode is chosen by bundle identifier so each `.app` enables
/// only its feature set:
///   - **Parrot** — grammar / fluency correction (Accessibility only).
///   - **Wren**   — inline completion + typo fix (Input Monitoring + optional Screen Recording).
enum AppMode {
    case parrot
    case wren

    static let current: AppMode = {
        let id = Bundle.main.bundleIdentifier ?? Constants.bundleID
        return id.localizedCaseInsensitiveContains("wren") ? .wren : .parrot
    }()

    /// On-demand grammar/fluency/translation correction of selected text.
    var showsCorrection: Bool { self == .parrot }
    /// Inline predictive completion + typo fix while typing.
    var showsCompletion: Bool { self == .wren }

    var displayName: String { self == .wren ? "Wren" : "Parrot" }
}
