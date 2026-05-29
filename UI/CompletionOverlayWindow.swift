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
        l.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.65)
        l.font = .systemFont(ofSize: NSFont.systemFontSize)
        return l
    }()

    func show(text: String, atCaretRect rect: CGRect) {
        guard !text.isEmpty, rect != .zero else { hide(); return }
        let panel = ensurePanel()
        label.stringValue = text
        label.sizeToFit()
        let size = label.frame.size
        // Place just to the right of the caret, vertically aligned with the caret rect.
        let origin = CGPoint(x: rect.maxX + 1, y: rect.minY)
        panel.setFrame(CGRect(origin: origin, size: CGSize(width: size.width + 4, height: max(size.height, rect.height))), display: true)
        label.frame = CGRect(x: 2, y: 0, width: size.width, height: panel.frame.height)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

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
        p.contentView?.addSubview(label)
        panel = p
        return p
    }
}
