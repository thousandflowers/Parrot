import Foundation
import Cocoa

struct ExtractedText: Sendable {
    let text: String
    let bundleID: String?
    let replacementRange: CFRange?
}

actor TextExtractionService: Sendable {
    static let shared = TextExtractionService()
    
    func extract(fromPID pid: pid_t? = nil) async throws -> ExtractedText {
        let text: String
        let bundleID: String?
        var replacementRange: CFRange? = nil
        
        if let pid = pid {
            do {
                text = try await AccessibilityBridge.shared.fetchSelectedText(fromPID: pid)
            } catch CorrectionError.noTextSelected {
                let (fallbackText, range) = try await AccessibilityBridge.shared.fetchTextOrLineAtCursor(fromPID: pid)
                text = fallbackText
                replacementRange = range
            }
            bundleID = await AppDetector.shared.frontAppBundleID(forPID: pid)
        } else {
            do {
                text = try await AccessibilityBridge.shared.fetchSelectedText()
            } catch CorrectionError.noTextSelected {
                let lastPID = await AccessibilityBridge.shared.lastKnownFrontAppPID()
                let (fallbackText, range) = try await AccessibilityBridge.shared.fetchTextOrLineAtCursor(fromPID: lastPID)
                text = fallbackText
                replacementRange = range
            }
            bundleID = await AccessibilityBridge.shared.frontAppBundleID()
        }
        
        guard !text.isEmpty else {
            throw CorrectionError.noTextSelected
        }
        
        return ExtractedText(text: text, bundleID: bundleID, replacementRange: replacementRange)
    }
}
