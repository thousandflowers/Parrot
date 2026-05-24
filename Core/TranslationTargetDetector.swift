import Cocoa
import Foundation

/// Infers the best translation target language from context signals.
///
/// Priority:
/// 1. Language of text surrounding the current selection (conversation partner's language)
/// 2. Language of the focused window title (platform language, e.g. taobao → zh)
/// 3. User's preferred translation language from preferences
enum TranslationTargetDetector {

    static func detect(
        sourceLanguage: String,
        pid: pid_t,
        selectionRange: CFRange
    ) async -> String {
        let fallback = await MainActor.run { PreferencesStore.shared.translationLanguage }

        // Signal 1: language of text surrounding the selection in the focused element.
        // Covers conversation contexts (eBay messages, chat apps) where the partner's
        // language appears around the composer field.
        let surrounding = await AccessibilityBridge.shared.fetchSurroundingText(
            pid: pid, selectionRange: selectionRange, windowSize: 400
        )
        if surrounding.count >= 40 {
            let detected = LanguageDetector.detect(text: surrounding, fallbackLanguage: "")
            if !detected.isEmpty && primaryCode(detected) != primaryCode(sourceLanguage) {
                return detected
            }
        }

        // Signal 2: language of the focused window title.
        // Covers platform-level detection (e.g. taobao window title is in Chinese).
        if let title = focusedWindowTitle(pid: pid), title.count >= 10 {
            let detected = LanguageDetector.detect(text: title, fallbackLanguage: "")
            if !detected.isEmpty && primaryCode(detected) != primaryCode(sourceLanguage) {
                return detected
            }
        }

        return fallback
    }

    // MARK: - Private

    private static func focusedWindowTitle(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &windowRef
        ) == .success,
              let wr = windowRef,
              let windowElement = AccessibilityBridge.asElementPublic(wr) else { return nil }
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            windowElement, kAXTitleAttribute as CFString, &titleRef
        ) == .success,
              let title = titleRef as? String else { return nil }
        return title
    }

    /// Compare by primary subtag only ("zh-Hans" == "zh-Hant" == "zh").
    private static func primaryCode(_ code: String) -> String {
        String(code.split(separator: "-").first ?? Substring(code))
    }
}
