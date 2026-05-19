import SwiftUI
import AppKit

// MARK: - Semantic color tokens

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
