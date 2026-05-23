import SwiftUI
import Cocoa

@MainActor
final class RealtimeIndicatorController {
    static let shared = RealtimeIndicatorController()

    private var window: NSWindow?
    private var hostingView: NSHostingView<RealtimeIndicatorView>?
    private var autoDismissTask: Task<Void, Never>?

    private init() {}

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // Only shows when there are actual errors. "All OK" is silent.
    func show(errors: Bool) {
        guard errors else {
            hide()
            return
        }

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

            let newView = RealtimeIndicatorView(hasErrors: true)

            if let existing = window {
                // Never update rootView on a visible window — NSHostingView.updateAnimatedWindowSize
                // fires from windowDidLayout and causes a re-entrant constraint crash.
                existing.orderOut(nil)
                let hv = NSHostingView(rootView: newView)
                hv.sizingOptions = []
                hostingView = hv
                existing.contentView = hv
                existing.setFrameOrigin(NSPoint(x: x, y: y))
                existing.orderFront(nil)
                fadeIn(existing)
            } else {
                let panel = NSWindow(
                    contentRect: NSRect(x: x, y: y, width: 130, height: 30),
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

                let hv = NSHostingView(rootView: newView)
                hv.sizingOptions = []
                hostingView = hv
                panel.contentView = hv
                window = panel
                panel.orderFront(nil)
                fadeIn(panel)
            }

            // Auto-dismiss after 4 seconds — avoid the popup lingering indefinitely.
            autoDismissTask?.cancel()
            autoDismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                await self?.hide()
            }
        }
    }

    func hide() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
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
            Text(hasErrors ? String(localized: "realtime.errors") : String(localized: "realtime.ok"))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                )
        )
    }
}
