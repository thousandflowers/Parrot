import SwiftUI
import Cocoa

@MainActor
final class RealtimeIndicatorController {
    static let shared = RealtimeIndicatorController()

    private var window: NSPanel?
    private var hostingView: NSHostingView<RealtimeIndicatorView>?

    private init() {}

    func show(errors: Bool, errorCount: Int = 0) {
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
                updateHostingView(hasErrors: errors, errorCount: errorCount)
                existing.orderFront(nil)
                return
            }

            let panel = NSPanel(
                contentRect: NSRect(x: x, y: y, width: 140, height: 36),
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

            let hv = NSHostingView(rootView: RealtimeIndicatorView(hasErrors: errors, errorCount: errorCount))
            hostingView = hv
            panel.contentView = hv
            window = panel
            panel.alphaValue = 0
            panel.orderFront(nil)
            await NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    private func updateHostingView(hasErrors: Bool, errorCount: Int) {
        let view = RealtimeIndicatorView(hasErrors: hasErrors, errorCount: errorCount)
        if let hv = hostingView {
            hv.rootView = view
        } else {
            let hv = NSHostingView(rootView: view)
            hostingView = hv
            window?.contentView = hv
        }
    }

    func hide() {
        window?.orderOut(nil)
    }
}

struct RealtimeIndicatorView: View {
    let hasErrors: Bool
    let errorCount: Int

    init(hasErrors: Bool, errorCount: Int = 0) {
        self.hasErrors = hasErrors
        self.errorCount = errorCount
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: hasErrors ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(hasErrors ? .refineWarning : .refineSuccess)
                .font(.system(size: 14))
                .accessibilityHidden(true)
            Text(hasErrors ? "\(errorCount) errori" : "OK")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                )
        )
    }
}
