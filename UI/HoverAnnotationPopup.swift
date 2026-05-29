import SwiftUI
import Cocoa

@MainActor
final class HoverAnnotationPopup {
    static let shared = HoverAnnotationPopup()
    private init() {}

    private var panel: NSPanel?
    private var hostingView: NSHostingView<HoverAnnotationView>?
    private(set) var currentAnnotation: ErrorAnnotation?
    private(set) var currentPID: pid_t = 0
    private var applyTask: Task<Void, Never>?

    var isVisible: Bool { panel?.isVisible == true }
    var windowFrame: NSRect { panel?.frame ?? .zero }

    func show(annotation: ErrorAnnotation, pid: pid_t, near rect: CGRect) {
        currentAnnotation = annotation
        currentPID = pid

        let text = annotation.suggestedFix.isEmpty ? annotation.originalSnippet : annotation.suggestedFix
        let estimatedW = max(90, CGFloat(text.count) * 8.0 + 52)
        let popupW = min(estimatedW, 260)
        let popupH: CGFloat = 28

        // Place above the annotation (higher Y = higher on screen in AppKit coords)
        let screen = NSScreen.main?.frame ?? .zero
        var x = rect.midX - popupW / 2
        var y = rect.maxY + 5

        x = max(8, min(screen.width - popupW - 8, x))
        if y + popupH > screen.height - 8 { y = rect.minY - popupH - 5 }

        if panel == nil { buildPanel() }
        updateContent(annotation: annotation)
        panel?.setFrame(NSRect(x: x, y: y, width: popupW, height: popupH), display: false)
        panel?.orderFrontRegardless()
    }

    func hide() {
        guard isVisible else { return }
        currentAnnotation = nil
        panel?.orderOut(nil)
    }

    func applyCurrentAnnotation() {
        guard let annotation = currentAnnotation else { return }
        let pid = currentPID
        guard !annotation.suggestedFix.isEmpty else {
            hide()
            return
        }
        applyTask?.cancel()
        applyTask = Task {
            do {
                try await AccessibilityBridge.shared.replaceRange(
                    annotation.charRange,
                    with: annotation.suggestedFix,
                    pid: pid
                )
                await MainActor.run {
                    self.hide()
                    InlineHighlightController.shared.clear()
                }
            } catch {
                // Text field might have changed — silently ignore
            }
        }
    }

    private func buildPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 28),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isMovable = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel = p
    }

    private func updateContent(annotation: ErrorAnnotation) {
        let view = HoverAnnotationView(
            annotation: annotation,
            onApply: { [weak self] in self?.applyCurrentAnnotation() }
        )
        // Never update rootView on a visible window — NSHostingView.updateAnimatedWindowSize
        // fires from windowDidLayout and causes a re-entrant constraint crash.
        // Always create a fresh NSHostingView; hide panel first if it is currently visible.
        if panel?.isVisible == true { panel?.orderOut(nil) }
        let hv = NSHostingView(rootView: view)
        hv.sizingOptions = []
        hv.setAccessibilityElement(true)
        hv.setAccessibilityLabel("Correction popup")
        hostingView = hv
        panel?.contentView = hv
    }
}

// MARK: - SwiftUI view

struct HoverAnnotationView: View {
    let annotation: ErrorAnnotation
    let onApply: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            if annotation.suggestedFix.isEmpty {
                Text(annotation.originalSnippet)
                    .strikethrough(true, color: Color.statusError)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(annotation.suggestedFix)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(action: onApply) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 16, height: 16)
                    .background(Color.statusOk, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Applica")
        }
        .padding(.leading, 8)
        .padding(.trailing, 5)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: .rect(cornerRadius: 7))
        .drawingGroup()
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.statusOk.opacity(0.3), lineWidth: 0.5)
        )
    }
}
