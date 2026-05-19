import Cocoa

@MainActor
final class DirectApplyToast {
    private static var currentWindow: NSPanel?
    private static var dismissTask: Task<Void, Never>?
    private static var undoOriginal: String?
    private static var undoPID: pid_t?

    static func show(message: String) {
        dismissTask?.cancel()
        currentWindow?.orderOut(nil)

        var unused: NSButton?
        let panel = buildPanel(message: message, showUndo: false, undoButton: &unused)
        currentWindow = panel
        panel.orderFrontRegardless()

        dismissTask = Task {
            try? await Task.sleep(for: .seconds(2))
            currentWindow?.orderOut(nil)
        }
    }

    static func showUndo(message: String, original: String, corrected: String, pid: pid_t) {
        dismissTask?.cancel()
        currentWindow?.orderOut(nil)
        undoOriginal = original
        undoPID = pid

        var undoButton: NSButton?
        let panel = buildPanel(message: message, showUndo: true, undoButton: &undoButton)

        undoButton?.target = DirectApplyToast.self
        undoButton?.action = #selector(performUndoAction)

        currentWindow = panel
        panel.orderFrontRegardless()

        dismissTask = Task {
            try? await Task.sleep(for: .seconds(5))
            currentWindow?.orderOut(nil)
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
        currentWindow?.orderOut(nil)
        currentWindow = nil
        show(message: "Correzione annullata")
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
        containerView.layer?.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 0.95).cgColor
        containerView.layer?.borderWidth = 0.5
        containerView.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
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
            let btn = NSButton(title: "Annulla", target: nil, action: nil)
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
