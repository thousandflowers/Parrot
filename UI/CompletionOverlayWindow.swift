import AppKit

/// A borderless, non-activating overlay that draws greyed ghost-completion text at the caret.
/// You cannot render into another app's text field, so this floats on top instead (same approach
/// as Cotypist). Positioning uses the caret rect from `AccessibilityBridge.boundsForRange`, which
/// is already in AppKit global coordinates (bottom-left origin).
@MainActor
final class CompletionOverlayWindow {
    private var panel: NSPanel?
    private let label: NSTextField = {
        let l = NSTextField(labelWithString: "")
        l.isBezeled = false
        l.drawsBackground = false
        l.isEditable = false
        l.isSelectable = false
        return l
    }()
    private var cachedFontSize: CGFloat = 0
    private var fontSizeObserver: Any?

    init() {
        cachedFontSize = readFontSize()
        fontSizeObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.cachedFontSize = self?.readFontSize() ?? 0
        }
    }

    private func readFontSize() -> CGFloat {
        let pref = PreferencesStore.shared.completionOverlayFontSize
        return pref > 0 ? pref : NSFont.systemFontSize(for: .regular)
    }

    func show(text: String, atCaretRect rect: CGRect, fontName: String? = nil, fontSize: CGFloat = 0) {
        guard !text.isEmpty, rect != .zero, !rect.isInfinite, !rect.isNull else { hide(); return }
        let panel = ensurePanel()
        // Attributed string: first word bold + brighter (partial-accept target), rest dimmed.
        let attributed = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: text.count)
        let size = fontSize > 0 ? fontSize : (cachedFontSize > 0 ? cachedFontSize : readFontSize())
        let baseFont = (fontName.flatMap { NSFont(name: $0, size: size) }) ?? NSFont.systemFont(ofSize: size)
        // Light text on the dark backdrop pill → readable regardless of the app's own colors.
        let baseColor = NSColor.ghostTextBase
        let firstWordColor = NSColor.ghostTextHighlight
        attributed.addAttribute(.font, value: baseFont, range: fullRange)
        attributed.addAttribute(.foregroundColor, value: baseColor, range: fullRange)

        if let firstSpace = text.firstIndex(of: " ") {
            let firstWordLen = text.distance(from: text.startIndex, to: firstSpace)
            let firstWordRange = NSRange(location: 0, length: firstWordLen)
            attributed.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: size), range: firstWordRange)
            attributed.addAttribute(.foregroundColor, value: firstWordColor, range: firstWordRange)
        } else {
            // Single word: highlight the entire thing
            attributed.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: size), range: fullRange)
            attributed.addAttribute(.foregroundColor, value: firstWordColor, range: fullRange)
        }

        label.attributedStringValue = attributed
        label.sizeToFit()
        let labelSize = label.frame.size
        let padX: CGFloat = 6, padY: CGFloat = 2
        let panelW = labelSize.width + padX * 2
        let panelH = max(labelSize.height + padY * 2, rect.height)
        // Place just to the right of the caret, then clamp to the screen that holds the caret so the
        // pill never renders off-window/off-screen (#2: "esce dalla finestra").
        var origin = CGPoint(x: rect.maxX + 3, y: rect.minY - padY)
        let caretPoint = CGPoint(x: rect.midX, y: rect.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(caretPoint) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            if origin.x + panelW > vf.maxX { origin.x = max(vf.minX, vf.maxX - panelW) }
            if origin.x < vf.minX { origin.x = vf.minX }
            if origin.y + panelH > vf.maxY { origin.y = vf.maxY - panelH }
            if origin.y < vf.minY { origin.y = vf.minY }
        }
        panel.setFrame(CGRect(origin: origin, size: CGSize(width: panelW, height: panelH)), display: true)
        label.frame = CGRect(x: padX, y: (panelH - labelSize.height) / 2, width: labelSize.width, height: labelSize.height)

        // Update AX label so VoiceOver can read the completion aloud.
        let axLabel = "Completion suggestion: \(text.prefix(120))"
        panel.setAccessibilityLabel(axLabel)
        // Post notification for screen readers.
        NSAccessibility.post(element: panel, notification: .announcementRequested)

        // Show crisply at full alpha — no fade. Combined with hide()-while-computing this gives a
        // single clean appear per pause instead of the old fade/dim flashing ("disturbato").
        panel.alphaValue = 1.0
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.alphaValue = 1.0
    }

    /// Called while a new suggestion is being computed. Hide the now-stale overlay cleanly rather
    /// than leaving a dimmed half-visible ghost — that partial-alpha flash was the "disturbo".
    func dim() { hide() }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        // AX: make the panel a container so VoiceOver can reach the completion text.
        // The old setAccessibilityElement(false) hid completions from blind users entirely.
        p.setAccessibilityElement(true)
        p.setAccessibilityRole(.staticText)
        // AX label is updated in show() to match the current completion text.
        // Native blur backdrop: readable on any app background, matches system HUD style.
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.state = .active
        blur.blendingMode = .behindWindow
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 5
        blur.layer?.masksToBounds = true
        blur.addSubview(label)
        // Keep label itself non-interactive but let the panel's AX tree expose it.
        label.setAccessibilityElement(false)
        p.contentView = blur
        panel = p
        return p
    }
}
