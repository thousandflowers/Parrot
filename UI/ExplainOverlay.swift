import SwiftUI
import AppKit
import OSLog

/// Inline explain/summarize popup: a compact overlay near the selected text that displays
/// an AI-generated explanation or summary. Single-use, dismiss with click-outside or Esc.
@MainActor
final class ExplainController {
    static let shared = ExplainController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<ExplainView>?
    private var clickMonitor: Any?

    private init() {}

    private var overlayScale: CGFloat {
        NSFont.systemFontSize / NSFont.systemFontSize(for: .regular)
    }

    func show(pid: pid_t, selectionRect: CGRect, mode: ExplainMode,
              text: String, bundleID: String?) {
        guard panel == nil else { return }

        let s = round(300 * overlayScale), sh = round(180 * overlayScale)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: s, height: sh),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = ExplainView(
            text: text, mode: mode, pid: pid,
            onDismiss: { [weak self] in self?.close() }
        )

        let hv = NSHostingView(rootView: view)
        hv.sizingOptions = []
        panel.contentView = hv

        let size = panel.frame.size
        var origin = NSPoint(x: selectionRect.midX - size.width / 2, y: selectionRect.minY - size.height - 8)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(selectionRect) }) ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            if origin.y < vf.minY { origin.y = selectionRect.maxY + 8 }
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

enum ExplainMode: String, CaseIterable {
    case explain = "Explain"
    case summarize = "Summarize"
    case simplify = "Simplify"

    var promptTemplate: String {
        switch self {
        case .explain:
            return """
            Explain the following text in simple terms. Be concise (2-3 sentences).
            
            Text:
            {{TEXT}}
            
            Explanation:
            """
        case .summarize:
            return """
            Summarize the following text in 1-2 sentences.
            
            Text:
            {{TEXT}}
            
            Summary:
            """
        case .simplify:
            return """
            Rewrite the following text to be simpler and easier to understand. Keep the same meaning.
            
            Text:
            {{TEXT}}
            
            Simplified:
            """
        }
    }
}

private struct ExplainView: View {
    let text: String
    let mode: ExplainMode
    let pid: pid_t
    let onDismiss: () -> Void

    @State private var result = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @ScaledMetric(relativeTo: .body) private var contentWidth: CGFloat = 300
    @ScaledMetric(relativeTo: .body) private var contentHeight: CGFloat = 180

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: modeIcon)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text(mode.rawValue)
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
                Text("Analyzing…")
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
                    .padding(.horizontal)
                Spacer()
            } else {
                ScrollView {
                    Text(result)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
                .frame(maxHeight: .infinity)

                HStack {
                    Spacer()
                    Button("Dismiss", action: onDismiss)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .frame(width: contentWidth, height: contentHeight)
        .background(Color.surfaceBackground)
        .task { await load() }
    }

    private var modeIcon: String {
        switch mode {
        case .explain: return "questionmark.circle.fill"
        case .summarize: return "text.alignleft"
        case .simplify: return "textformat.size"
        }
    }

    private func load() async {
        do {
            let customPrompt = CustomPrompt(id: UUID(), name: mode.rawValue,
                                            template: mode.promptTemplate, checkType: .custom)
            let llmResult = try await RequestQueue.shared.enqueue(
                text: text, type: .grammar, priority: .manual,
                overrideServiceType: nil, overrideCustomPrompt: customPrompt
            )
            result = llmResult.correctedText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if result.isEmpty { result = "No analysis available." }
        } catch {
            errorMessage = "Analysis failed"
            CrashLogger.log("explain: \(mode.rawValue) failed — \(error.localizedDescription)")
        }
        isLoading = false
    }
}
