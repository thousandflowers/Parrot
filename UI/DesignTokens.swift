import SwiftUI
import AppKit

extension Color {
    /// Stato positivo / conferma — verde adattivo a light e dark mode
    static let statusOk = Color(nsColor: NSColor.systemGreen)

    /// Avviso / attenzione — arancione adattivo a light e dark mode
    static let statusWarning = Color(nsColor: NSColor.systemOrange)

    /// Errore / critico — rosso adattivo a light e dark mode
    static let statusError = Color(nsColor: NSColor.systemRed)

    /// Stato inattivo / neutro — grigio adattivo (secondary label)
    static let statusInactive = Color(nsColor: NSColor.secondaryLabelColor)

    /// Colore accent / brand — blu adattivo a light e dark mode
    static let accentBrand = Color(nsColor: NSColor.systemBlue)

    /// Testo primario — mappa al colore primario del sistema (nero in light, bianco in dark)
    static let textPrimary = Color.primary

    /// Testo secondario — mappa al colore secondario del sistema
    static let textSecondary = Color.secondary
}

extension View {
    /// Rimuove elementi AX "fantasma" (size 0x0) tipici di ScrollView/List su macOS
    func cleanAccessibilityTree() -> some View {
        self.accessibilityElement(children: .contain)
            .accessibilityHidden(false)
    }
}
