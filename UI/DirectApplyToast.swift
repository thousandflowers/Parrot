import Cocoa

@MainActor
final class DirectApplyToast {
    private static var currentWindow: NSPanel?
    private static var dismissTask: Task<Void, Never>?
    private static var undoOriginal: String?
    private static var undoPID: pid_t?

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

    static func showUndo(message: String, original: String, corrected: String, pid: pid_t) {
        dismissTask?.cancel()
        dismissAnimated(currentWindow)
        undoOriginal = original
        undoPID = pid

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
        Task {
            do {
                try await AccessibilityBridge.shared.replaceSelectedText(with: original)
            } catch {
                // Cmd+Z available as manual fallback
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
            btn.contentTintColor = NSColor.systemBlue
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

        let mouse = NSEvent.mouseLocation
        let origin = NSPoint(x: mouse.x + 20, y: mouse.y - 60)
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            let clampedX = max(frame.minX, min(frame.maxX - size.width, origin.x))
            let clampedY = max(frame.minY, min(frame.maxY - size.height, origin.y))
            panel.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
        } else {
            panel.setFrameOrigin(origin)
        }

        return panel
    }
}
