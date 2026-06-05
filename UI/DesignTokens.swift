import SwiftUI
import AppKit

extension NSColor {
    static let statusOk = appearanceColor(
        light: NSColor(displayP3Red: 0.20, green: 0.72, blue: 0.35, alpha: 1),
        dark: NSColor(displayP3Red: 0.30, green: 0.82, blue: 0.48, alpha: 1)
    )
    static let statusWarning = appearanceColor(
        light: NSColor(displayP3Red: 0.85, green: 0.55, blue: 0.10, alpha: 1),
        dark: NSColor(displayP3Red: 0.95, green: 0.70, blue: 0.25, alpha: 1)
    )
    static let statusError = appearanceColor(
        light: NSColor(displayP3Red: 0.80, green: 0.18, blue: 0.16, alpha: 1),
        dark: NSColor(displayP3Red: 0.92, green: 0.30, blue: 0.24, alpha: 1)
    )
    static let statusInactive = appearanceColor(
        light: NSColor(displayP3Red: 0.55, green: 0.55, blue: 0.55, alpha: 1),
        dark: NSColor(displayP3Red: 0.50, green: 0.50, blue: 0.50, alpha: 1)
    )

    static let surfaceWarm = appearanceColor(
        light: NSColor(displayP3Red: 0.97, green: 0.96, blue: 0.94, alpha: 1),
        dark: NSColor(displayP3Red: 0.15, green: 0.14, blue: 0.13, alpha: 1)
    )
    static let borderWarm = appearanceColor(
        light: NSColor(displayP3Red: 0.88, green: 0.86, blue: 0.83, alpha: 1),
        dark: NSColor(displayP3Red: 0.30, green: 0.28, blue: 0.26, alpha: 1)
    )

    // Parrot eye (custom NSBezierPath drawing in the menu bar icon)
    static let eyeSurface = appearanceColor(
        light: NSColor.white,
        dark: NSColor(white: 0.2, alpha: 1)
    )

    // Generic surfaces
    static let surfaceBackground = appearanceColor(
        light: NSColor(displayP3Red: 0.96, green: 0.97, blue: 0.98, alpha: 1),
        dark: NSColor(displayP3Red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    )
    static let surfaceElevated = appearanceColor(
        light: NSColor(displayP3Red: 0.99, green: 0.99, blue: 1.0, alpha: 1),
        dark: NSColor(displayP3Red: 0.17, green: 0.17, blue: 0.18, alpha: 1)
    )
    static let borderDefault = appearanceColor(
        light: NSColor(displayP3Red: 0.80, green: 0.80, blue: 0.82, alpha: 1),
        dark: NSColor(displayP3Red: 0.32, green: 0.32, blue: 0.34, alpha: 1)
    )

    static func appearanceColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.name == .darkAqua || appearance.name == .vibrantDark
            return isDark ? dark : light
        }
    }
}

extension Color {
    static let statusOk = Color(nsColor: .statusOk)
    static let statusWarning = Color(nsColor: .statusWarning)
    static let statusError = Color(nsColor: .statusError)
    static let statusInactive = Color(nsColor: .statusInactive)
    static let surfaceWarm = Color(nsColor: .surfaceWarm)
    static let borderWarm = Color(nsColor: .borderWarm)
    static let surfaceBackground = Color(nsColor: .surfaceBackground)
    static let surfaceElevated = Color(nsColor: .surfaceElevated)
    static let borderDefault = Color(nsColor: .borderDefault)

    static let accentBrand = Color.accentColor
    static let accentGreen = Color(nsColor: .statusOk)
    static let accentPurple = Color(nsColor: NSColor.appearanceColor(
        light: NSColor(displayP3Red: 0.55, green: 0.30, blue: 0.52, alpha: 1),
        dark: NSColor(displayP3Red: 0.78, green: 0.52, blue: 0.72, alpha: 1)
    ))
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
}

// MARK: - Colorblind-safe diff colors
// Uses blue/orange instead of red/green so the ~8% of users with colorblindness
// can distinguish insertions from deletions. Patterns (strikethrough/underline)
// provide an additional differentiation channel.
extension NSColor {
    /// Deletion (was red): now blue with strikethrough for colorblind safety.
    static let diffDeletion = appearanceColor(
        light: NSColor(displayP3Red: 0.20, green: 0.45, blue: 1.0, alpha: 1),
        dark: NSColor(displayP3Red: 0.35, green: 0.55, blue: 1.0, alpha: 1)
    )
    static let diffDeletionBackground = appearanceColor(
        light: NSColor(displayP3Red: 0.20, green: 0.45, blue: 1.0, alpha: 0.12),
        dark: NSColor(displayP3Red: 0.35, green: 0.55, blue: 1.0, alpha: 0.18)
    )
    /// Insertion (was green): now orange with underline for colorblind safety.
    static let diffInsertion = appearanceColor(
        light: NSColor(displayP3Red: 0.90, green: 0.55, blue: 0.05, alpha: 1),
        dark: NSColor(displayP3Red: 1.0, green: 0.68, blue: 0.15, alpha: 1)
    )
    static let diffInsertionBackground = appearanceColor(
        light: NSColor(displayP3Red: 0.90, green: 0.55, blue: 0.05, alpha: 0.12),
        dark: NSColor(displayP3Red: 1.0, green: 0.68, blue: 0.15, alpha: 0.18)
    )

    /// Ghost completion text — dimmed base, highlighted first word (partial-accept target)
    static let ghostTextBase = NSColor(calibratedWhite: 1.0, alpha: 0.72)
    static let ghostTextHighlight = NSColor(calibratedWhite: 1.0, alpha: 0.98)
}

extension Color {
    static let diffDeletion = Color(nsColor: .diffDeletion)
    static let diffDeletionBackground = Color(nsColor: .diffDeletionBackground)
    static let diffInsertion = Color(nsColor: .diffInsertion)
    static let diffInsertionBackground = Color(nsColor: .diffInsertionBackground)
}

// MARK: - Card style modifier (replaces 15+ copies of RoundedRectangle + overlay)
struct CardStyle: ViewModifier {
    let radius: CGFloat
    let borderOpacity: CGFloat

    init(radius: CGFloat = 10, borderOpacity: CGFloat = 0.5) {
        self.radius = radius
        self.borderOpacity = borderOpacity
    }

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.separator.opacity(borderOpacity), lineWidth: 0.5)
            )
    }
}

extension View {
    func cardStyle(radius: CGFloat = 10, borderOpacity: CGFloat = 0.5) -> some View {
        modifier(CardStyle(radius: radius, borderOpacity: borderOpacity))
    }
}
