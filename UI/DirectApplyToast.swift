import Cocoa
import OSLog

@MainActor
final class DirectApplyToast {
    private static var currentWindow: NSPanel?
    private static var dismissTask: Task<Void, Never>?
    private static var undoOriginal: String?
    private static var undoPID: pid_t?
    private static var undoRange: CFRange?
    private static var undoCorrected: String?

    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private static let successMessages: [String] = [
        "✓ Text corrected",
        "✓ All good!",
        "✓ Done",
        "✓ Polished",
        "✓ Sorted",
    ]
    private static var messageIndex = 0

    static func show(message: String) {
        dismissTask?.cancel()
        dismissAnimated(currentWindow)

        var unused: NSButton?
        // Rotate success messages for positive outcomes
        let display = message.hasPrefix("✓") ? message : message
        let panel = buildPanel(message: display, showUndo: false, undoButton: &unused)
        currentWindow = panel
        showAnimated(panel)

        dismissTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            dismissAnimated(currentWindow)
            currentWindow = nil
        }
    }

    static func showSuccess() {
        messageIndex = (messageIndex + 1) % successMessages.count
        show(message: successMessages[messageIndex])
    }

    static func showUndo(message: String, original: String, corrected: String, pid: pid_t, range: CFRange? = nil) {
        dismissTask?.cancel()
        dismissAnimated(currentWindow)
        undoOriginal = original
        undoCorrected = corrected
        undoPID = pid
        undoRange = range

        var undoButton: NSButton?
        let panel = buildPanel(message: message, showUndo: true, undoButton: &undoButton)

        undoButton?.target = DirectApplyToast.self
        undoButton?.action = #selector(performUndoAction)

        currentWindow = panel
        showAnimated(panel)

        dismissTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            dismissAnimated(currentWindow)
            currentWindow = nil
        }
    }

    @objc private static func performUndoAction() {
        dismissTask?.cancel()
        guard let original = undoOriginal else { return }
        let range = undoRange
        let pid = undoPID
        // With a captured span, only undo while it still holds what we wrote.
        let expected = range == nil ? nil : undoCorrected
        Task {
            do {
                _ = try await AccessibilityBridge.shared.replaceSelectedText(
                    with: original, range: range, expectedPID: pid, expectedText: expected)
            } catch {
                Logger.ui.error("DirectApplyToast: undo failed: \(error.localizedDescription)")
                await MainActor.run { show(message: "Couldn't undo — press ⌘Z in the app") }
            }
        }
        dismissAnimated(currentWindow)
        currentWindow = nil
        show(message: "Correction undone")
    }

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

    private static func buildPanel(message: String, showUndo: Bool, undoButton: inout NSButton?) -> NSPanel {
        let size = NSSize(width: showUndo ? 280 : 220, height: 44)
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

        let containerView = NSView(frame: NSRect(origin: .zero, size: size))
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 10
        containerView.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.96).cgColor
        containerView.layer?.borderWidth = 1
        containerView.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = NSColor.labelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(label)

        var labelConstraints: [NSLayoutConstraint] = [
            label.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
        ]
        if !showUndo {
            labelConstraints.append(label.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16))
        }
        NSLayoutConstraint.activate(labelConstraints)

        if showUndo {
            let btn = NSButton(title: "Undo", target: nil, action: nil)
            btn.bezelStyle = .regularSquare
            btn.isBordered = false
            btn.contentTintColor = NSColor.controlAccentColor
            btn.font = .systemFont(ofSize: 13, weight: .medium)
            btn.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(btn)
            undoButton = btn

            label.trailingAnchor.constraint(equalTo: btn.leadingAnchor, constant: -8).isActive = true

            NSLayoutConstraint.activate([
                btn.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
                btn.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            ])
        }

        panel.contentView = containerView

        // Clamp into the screen the MOUSE is on (the toast is placed next to it), not NSScreen.main.
        let mouse = NSEvent.mouseLocation
        let frame = NSRect(origin: NSPoint(x: mouse.x + 20, y: mouse.y - 60), size: size)
        panel.setFrameOrigin(ScreenGeometry.clamp(frame, toScreenFor: NSRect(origin: mouse, size: .zero)).origin)

        return panel
    }
}
