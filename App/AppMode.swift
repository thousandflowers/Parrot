import Foundation

/// Parrot and Canary ship from one codebase as two separate apps (distinct bundles, icons,
/// identities, and permissions). The mode is chosen by bundle identifier so each `.app` enables
/// only its feature set:
///   - **Parrot**  — grammar / fluency correction (Accessibility only).
///   - **Canary**  — inline completion + typo fix (Input Monitoring + optional Screen Recording).
enum AppMode {
    case parrot
    case canary

    static let current: AppMode = {
        let id = Bundle.main.bundleIdentifier ?? Constants.bundleID
        return id.localizedCaseInsensitiveContains("canary") ? .canary : .parrot
    }()

    /// On-demand grammar/fluency/translation correction of selected text.
    var showsCorrection: Bool { self == .parrot }
    /// Inline predictive completion + typo fix while typing.
    var showsCompletion: Bool { self == .canary }

    var displayName: String { self == .canary ? "Canary" : "Parrot" }
}
