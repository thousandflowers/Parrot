import SwiftUI
import AppKit

// MARK: - Semantic color tokens for RefineClone
//
// These provide a single source of truth for all semantic colors.
// To change the success color app-wide, edit it in one place.

extension Color {
    static let refineSuccess = Color.green
    static let refineError = Color.red
    static let refineWarning = Color.orange
    static let refineFluency = Color.blue
}

extension NSColor {
    static let refineSuccess = NSColor.systemGreen
    static let refineError = NSColor.systemRed
    static let refineWarning = NSColor.systemOrange
    static let refineFluency = NSColor.systemBlue
}
