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

    private static func appearanceColor(light: NSColor, dark: NSColor) -> NSColor {
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
    static let accentPurple = Color.accentColor
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
}

extension View {
    func cleanAccessibilityTree() -> some View {
        self.accessibilityElement(children: .contain)
            .accessibilityHidden(false)
    }
}
