import Cocoa
import SwiftUI

@MainActor
final class FocusCelebration {
    static let shared = FocusCelebration()

    private static var currentToast: NSPanel?
    private static var dismissTask: Task<Void, Never>?

    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private init() {}

    // MARK: - Public

    func celebrateSessionComplete(words: Int, minutes: Int) {
        let prefs = PreferencesStore.shared

        if prefs.focusCelebrateSound {
            playCompletionSound()
        }

        if prefs.focusCelebrateToast {
            showCompletionToast(words: words, minutes: minutes)
        }

        if prefs.focusCelebrateStreak {
            checkStreakMilestone()
        }
    }

    // MARK: - Sound

    private func playCompletionSound() {
        NSSound(named: "Tink")?.play()
    }

    // MARK: - Toast

    private func showCompletionToast(words: Int, minutes: Int) {
        Self.dismissTask?.cancel()
        Self.dismissAnimated(Self.currentToast)

        let msg = words > 0
            ? "✓ Session done · \(minutes)m · \(words) words"
            : "✓ Session done · \(minutes)m"

        let panel = Self.buildToast(message: msg)
        Self.currentToast = panel
        Self.showAnimated(panel)

        Self.dismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            Self.dismissAnimated(Self.currentToast)
            Self.currentToast = nil
        }
    }

    // MARK: - Streak milestone

    private func checkStreakMilestone() {
        let stats = FocusStatsStore.shared
        let streak = stats.currentStreak
        guard streak > 1 else { return }

        let milestones = [3, 5, 7, 14, 21, 30, 50, 100]
        guard milestones.contains(streak) else { return }

        let alert = NSAlert()
        alert.messageText = "\(streak)-day streak! 🔥"
        alert.informativeText = streak >= 30
            ? "Incredible discipline! You've written with focus for \(streak) consecutive days."
            : streak >= 7
                ? "Consistency pays off — \(streak) days and counting. Keep going!"
                : "Great start! \(streak) days in a row. You're building a habit."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Keep going")
        alert.runModal()
    }

    // MARK: - Toast panel

    private static func showAnimated(_ panel: NSPanel) {
        panel.orderFrontRegardless()
        guard !reduceMotion, let layer = panel.contentView?.layer else { return }
        layer.opacity = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.opacity = 1
        }
    }

    private static func dismissAnimated(_ panel: NSPanel?) {
        guard let panel, !reduceMotion, let layer = panel.contentView?.layer else {
            panel?.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.opacity = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    private static func buildToast(message: String) -> NSPanel {
        let size = NSSize(width: 260, height: 44)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.maxSize = size

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.96).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = NSColor.labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
        ])

        panel.contentView = container

        // Position near menu bar, center of screen
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            let x = frame.midX - size.width / 2
            let y = frame.maxY - size.height - 20
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        return panel
    }
}
