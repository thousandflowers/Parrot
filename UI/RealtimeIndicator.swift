import SwiftUI
import Cocoa

@MainActor
final class RealtimeIndicatorController {
    static let shared = RealtimeIndicatorController()

    private var window: NSWindow?

    private init() {}

    func show(errors: Bool) {
        Task { @MainActor in
            let bounds = await AccessibilityBridge.shared.lastSelectionBounds
            let mousePoint = NSEvent.mouseLocation
            let x: CGFloat
            let y: CGFloat
            if bounds != .zero {
                x = bounds.maxX + 16
                y = bounds.maxY - 24
            } else {
                x = mousePoint.x + 20
                y = mousePoint.y - 20
            }

            if let existing = window {
                existing.setFrameOrigin(NSPoint(x: x, y: y))
                existing.orderFront(nil)
                existing.contentView = NSHostingView(rootView: RealtimeIndicatorView(hasErrors: errors))
                return
            }

            let panel = NSWindow(
                contentRect: NSRect(x: x, y: y, width: 120, height: 36),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isReleasedWhenClosed = false

            panel.contentView = NSHostingView(rootView: RealtimeIndicatorView(hasErrors: errors))
            window = panel
            panel.orderFront(nil)
        }
    }

    func hide() {
        window?.orderOut(nil)
    }
}

struct RealtimeIndicatorView: View {
    let hasErrors: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: hasErrors ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(hasErrors ? .orange : .green)
                .font(.system(size: 14))
            Text(hasErrors ? "Errori" : "OK")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                )
        )
    }
}
