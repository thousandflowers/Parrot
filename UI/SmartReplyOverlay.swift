import SwiftUI
import AppKit
import OSLog

/// Smart Reply: reads recent screen context (conversation/email above caret), classifies as
/// email/chat, generates 2-3 reply suggestions, shows in a compact popup for one-tap insert.
@MainActor
final class SmartReplyController {
    static let shared = SmartReplyController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<SmartReplyView>?
    private var clickMonitor: Any?

    private init() {}

    func show(pid: pid_t, caretRect: CGRect, bundleID: String?) {
        guard panel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = SmartReplyView(
            pid: pid,
            caretRect: caretRect,
            bundleID: bundleID,
            onSelect: { [weak self] reply, pid in
                guard let self else { return }
                self.close()
                Task {
                    _ = await AccessibilityBridge.shared.insertCompletion(reply, pid: pid)
                    DirectApplyToast.show(message: "✓ Reply inserted")
                    Logger.infra.debug("smart-reply: inserted '\(reply.prefix(30))'")
                }
            },
            onDismiss: { [weak self] in self?.close() }
        )

        let hv = NSHostingView(rootView: view)
        hv.sizingOptions = []
        panel.contentView = hv

        let size = panel.frame.size
        var origin = NSPoint(x: caretRect.midX - size.width / 2, y: caretRect.minY - size.height - 8)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(caretRect) }) ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            if origin.y < vf.minY { origin.y = caretRect.maxY + 8 }
            if origin.x < vf.minX { origin.x = vf.minX }
            if origin.x + size.width > vf.maxX { origin.x = vf.maxX - size.width }
        }
        panel.setFrameOrigin(origin)

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
}

private struct SmartReplyView: View {
    let pid: pid_t
    let caretRect: CGRect
    let bundleID: String?
    let onSelect: (String, pid_t) -> Void
    let onDismiss: () -> Void

    @State private var replies: [String] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Smart Reply")
                    .font(.headline.weight(.semibold))
                Spacer()
                Button("✕", action: onDismiss)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .accessibilityLabel("Close")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Text("Generating replies…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else if let err = errorMessage {
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.statusWarning)
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(replies.enumerated()), id: \.offset) { idx, reply in
                            Button(action: { onSelect(reply, pid) }) {
                                Text(reply)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Reply \(idx + 1): \(reply)")
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(maxHeight: 140)
            }
        }
        .frame(width: 320, height: 220)
        .background(Color.surfaceBackground)
        .task { await loadReplies() }
    }

    private func loadReplies() async {
        let screenH = NSScreen.main?.frame.height ?? 0
        var context = await ScreenContextProvider.shared.currentContext(pid: pid, caretRect: caretRect, screenHeight: screenH)
        if context.isEmpty {
            context = await AccessibilityBridge.shared.completionContext(pid: pid)?.preContext ?? ""
        }
        guard !context.isEmpty else {
            errorMessage = "No conversation context found"
            isLoading = false
            return
        }

        let promptText: String
        if let bundleID, let cat = AppCategory(rawValue: AppCategory.detect(bundleID: bundleID).rawValue) {
            switch cat {
            case .email:
                promptText = "You are replying to an email. Read the email thread above and write 2-3 concise, natural reply options. Each on a new line starting with '- '."
            case .chat:
                promptText = "You are in a chat conversation. Write 2-3 natural, short replies. Each on a new line starting with '- '."
            default:
                promptText = "Read the conversation context above. Write 2-3 natural reply options. Each on a new line starting with '- '."
            }
        } else {
            promptText = "Read the conversation context above. Write 2-3 natural reply options. Each on a new line starting with '- '."
        }

        let fullPrompt = promptText + "\n\nContext:\n" + context

        do {
            let customPrompt = CustomPrompt(id: UUID(), name: "Smart Reply", template: fullPrompt, checkType: .custom)
            let result = try await RequestQueue.shared.enqueue(
                text: "Write reply options.", type: .grammar, priority: .manual,
                overrideServiceType: nil, overrideCustomPrompt: customPrompt
            )
            let lines = result.correctedText
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("- ") }
                .map { String($0.dropFirst(2)) }
            if lines.isEmpty {
                replies = [result.correctedText.trimmingCharacters(in: .whitespaces)]
            } else {
                replies = Array(lines.prefix(3))
            }
        } catch {
            errorMessage = "Failed to generate replies"
            CrashLogger.log("smart-reply: generation failed — \(error.localizedDescription)")
        }
        isLoading = false
    }
}
