import SwiftUI
import Cocoa

@MainActor
final class RealtimeIndicatorController {
    static let shared = RealtimeIndicatorController()

    private var window: NSWindow?

    private init() {}

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func show(errors: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
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
                existing.contentView = NSHostingView(rootView: RealtimeIndicatorView(hasErrors: errors))
                if existing.alphaValue < 1.0 {
                    existing.orderFront(nil)
                    fadeIn(existing)
                }
                return
            }

            let panel = NSWindow(
                contentRect: NSRect(x: x, y: y, width: 130, height: 36),
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
            fadeIn(panel)
        }
    }

    func hide() {
        guard let window = window else { return }
        if reduceMotion {
            window.orderOut(nil)
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                ctx.completionHandler = { window.orderOut(nil) }
                window.animator().alphaValue = 0
            }
        }
    }

    private func fadeIn(_ window: NSWindow) {
        guard !reduceMotion else { return }
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }
    }
}

struct RealtimeIndicatorView: View {
    let hasErrors: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: hasErrors ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(hasErrors ? .statusWarning : .statusOk)
                .font(.callout)
            Text(hasErrors ? "Errori" : "OK")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.textPrimary)
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
