import SwiftUI
import AppKit
import OSLog

/// Quick compose popup: 300×200, text field + submit, appears at cursor, single-use.
@MainActor
final class ComposeController {
    static let shared = ComposeController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<ComposeView>?
    private var clickMonitor: Any?

    private init() {}

    func show(pid: pid_t = 0, caretRect: CGRect = .zero) {
        if panel != nil { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true

        let view = ComposeView(
            onSubmit: { [weak self] text in
                guard let self else { return }
                self.submit(text: text, pid: pid)
            },
            onDismiss: { [weak self] in self?.close() }
        )
        let hv = NSHostingView(rootView: view)
        hv.sizingOptions = []
        panel.contentView = hv

        // Position at caret or mouse
        let size = panel.frame.size
        let origin: NSPoint
        if caretRect != .zero {
            origin = NSPoint(x: caretRect.midX - size.width / 2, y: caretRect.minY - size.height - 8)
        } else {
            let mouse = NSEvent.mouseLocation
            origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2)
        }
        panel.setFrameOrigin(clampToScreen(origin, size: size))

        self.panel = panel
        self.hostingView = hv
        panel.orderFrontRegardless()

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let p = self.panel, !p.frame.contains(NSEvent.mouseLocation) else { return }
            Task { @MainActor in self.close() }
        }
    }

    func close() {
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor); clickMonitor = nil }
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    private func submit(text: String, pid: pid_t) {
        close()
        Task {
            do {
                let result = try await RequestQueue.shared.enqueue(
                    text: text, type: .aiPrompt, priority: .manual,
                    overrideServiceType: nil, overrideCustomPrompt: nil
                )
                if pid != 0 {
                    _ = await AccessibilityBridge.shared.insertCompletion(result.correctedText, pid: pid)
                }
                DirectApplyToast.show(message: "✓ Done")
                Logger.infra.debug("compose: submitted \(text.prefix(20)) → \(result.correctedText.prefix(30))")
            } catch {
                Logger.infra.error("compose: failed — \(error.localizedDescription)")
                DirectApplyToast.show(message: "✗ Failed")
            }
        }
    }

    private func clampToScreen(_ origin: NSPoint, size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(origin) }) ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return origin }
        let x = max(vf.minX, min(vf.maxX - size.width, origin.x))
        let y = max(vf.minY, min(vf.maxY - size.height, origin.y))
        return NSPoint(x: x, y: y)
    }
}

private struct ComposeView: View {
    let onSubmit: (String) -> Void
    let onDismiss: () -> Void
    @State private var text = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("AI Compose")
                    .font(.headline.weight(.semibold))
                Spacer()
                Button("✕", action: onDismiss)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .accessibilityLabel("Close")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            TextEditor(text: $text)
                .font(.system(.body, design: .default))
                .scrollContentBackground(.hidden)
                .background(.fill.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
                )
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 16)

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Compose") {
                    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    onSubmit(text)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: 300, height: 200)
        .background(Color.surfaceBackground)
    }
}
