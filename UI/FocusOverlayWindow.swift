import AppKit
import SwiftUI

/// Floating overlay showing the focus timer, word count, and streak.
/// Reuses the same pattern as CompletionOverlayWindow — a borderless,
/// always-on-top NSWindow that follows the active screen area.
@MainActor
final class FocusOverlayWindow {
    static let shared = FocusOverlayWindow()

    private var window: NSWindow?
    private var size: NSSize {
        let scale = NSFont.systemFontSize / NSFont.systemFontSize(for: .regular)
        return NSSize(width: round(280 * scale), height: round(120 * scale))
    }
    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private init() {}

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            if !reduceMotion, existing.alphaValue < 1.0 { fadeIn(existing) }
            return
        }

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let origin = NSPoint(
            x: screenFrame.maxX - size.width - 20,
            y: screenFrame.maxY - size.height - 20
        )

        let newWindow = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newWindow.level = .floating
        newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        newWindow.isReleasedWhenClosed = false
        newWindow.backgroundColor = .clear
        newWindow.isMovableByWindowBackground = true
        newWindow.title = "Focus Timer"
        newWindow.contentView = NSHostingView(rootView: FocusOverlayContent())
        // Round corners via mask
        newWindow.contentView?.wantsLayer = true
        newWindow.contentView?.layer?.cornerRadius = 14
        newWindow.contentView?.layer?.masksToBounds = true

        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        fadeIn(newWindow)
    }

    func hide() {
        guard let w = window else { return }
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                w.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    guard let w = self.window else { return }
                    w.alphaValue = 1
                    w.orderOut(nil)
                    self.window = nil
                }
            }
        } else {
            window?.orderOut(nil)
            window = nil
        }
    }

    func updatePosition() {
        guard let w = window else { return }
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let origin = NSPoint(
            x: screenFrame.maxX - size.width - 20,
            y: screenFrame.maxY - size.height - 20
        )
        w.setFrameOrigin(origin)
    }

    private func fadeIn(_ window: NSWindow) {
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }
    }
}

// MARK: - Content View

struct FocusOverlayContent: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var timer = FocusTimer.shared
    @StateObject private var stats = FocusStatsStore.shared
    @StateObject private var focusMode = FocusMode.shared
    @ScaledMetric(relativeTo: .body) private var contentWidth: CGFloat = 280
    @ScaledMetric(relativeTo: .body) private var contentHeight: CGFloat = 70

    var body: some View {
        HStack(spacing: 12) {
            // Timer circle
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                    .frame(width: 48, height: 48)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: .init(lineWidth: 3, lineCap: .round))
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: progress)
                Text(timeString)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            // Stats
            VStack(alignment: .leading, spacing: 2) {
                Text("Focus mode")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("\(stats.todayWords) words · \(stats.todayMinutes)m today")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if stats.currentStreak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        Text("\(stats.currentStreak)-day streak")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            // Controls
            VStack(spacing: 4) {
                Button {
                    if timer.isPaused { timer.resume() } else { timer.pause() }
                } label: {
                    Image(systemName: timer.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 12))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(timer.isPaused ? "Resume session" : "Pause session")

                Button {
                    timer.endEarly()
                    FocusOverlayWindow.shared.hide()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Stop session")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Group {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.surfaceElevated)
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.thinMaterial)
                }
            }
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        )
        .frame(width: contentWidth, height: contentHeight)
        .onChange(of: timer.timerState) { _, newState in
            switch newState {
            case .finished, .idle:
                FocusOverlayWindow.shared.hide()
            default:
                break
            }
        }
    }

    private var progress: CGFloat {
        guard case .running(let dur, _) = timer.timerState, dur > 0 else { return 0 }
        return CGFloat(timer.elapsedSeconds) / CGFloat(dur)
    }

    private var timeString: String {
        let rem = timer.remainingSeconds
        let m = rem / 60
        let s = rem % 60
        return String(format: "%d:%02d", m, s)
    }
}
