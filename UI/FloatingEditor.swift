import SwiftUI
import Cocoa

@MainActor
final class FloatingEditorController {
    static let shared = FloatingEditorController()

    private var window: NSWindow?

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            if !reduceMotion, existing.alphaValue < 1.0 { fadeIn(existing) }
            return
        }

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Editor — Refine"
        newWindow.subtitle = "Correct and improve your text"
        newWindow.level = .floating
        newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.setFrameAutosaveName("FloatingEditorWindow")

        newWindow.contentView = NSHostingView(rootView: FloatingEditorView(onDismiss: { [weak self] in
            self?.close()
        }))

        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        fadeIn(newWindow)
    }

    private func fadeIn(_ window: NSWindow) {
        guard !reduceMotion else { return }
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }
    }

    private func close() {
        window?.close()
        window = nil
    }
}

struct FloatingEditorView: View {
    let onDismiss: () -> Void

    @State private var inputText: String = ""
    @State private var correctedText: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var checkMode: CheckMode = .grammar
    @State private var checkTask: Task<Void, Never>?

    enum CheckMode: String, CaseIterable {
        case grammar = "grammar"
        case fluency = "fluency"

        var displayName: String {
            switch self {
            case .grammar: return String(localized: "editor.mode.grammar")
            case .fluency: return String(localized: "editor.mode.fluency")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            splitContent
            Divider()
            bottomBar
        }
        .frame(minWidth: 560, minHeight: 320)
        .onDisappear { checkTask?.cancel() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $checkMode) {
                ForEach(CheckMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .labelsHidden()

            Spacer()

            if isLoading {
                ProgressView().scaleEffect(0.7).frame(width: 16, height: 16)
                Text("Processing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            wordCountBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var wordCountBadge: some View {
        if !inputText.isEmpty {
            let wc = inputText.split(separator: " ").count
            let cc = inputText.count
            HStack(spacing: 10) {
                Text("\(wc) words")
                Text("\(cc) chr.")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Split Content

    private var splitContent: some View {
        HStack(spacing: 0) {
            editorPane
            Divider()
            outputPane
        }
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Original")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            TextEditor(text: $inputText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .background(.clear)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .frame(minWidth: 240)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var outputPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Corrected")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if !correctedText.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(correctedText, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Copy corrected text")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ScrollView {
                if correctedText.isEmpty && !isLoading {
                    Text("The corrected text will appear here")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                } else {
                    DiffHighlightView(
                        original: inputText,
                        corrected: correctedText.isEmpty ? inputText : correctedText
                    )
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
                }
            }
            .frame(minWidth: 240)
            .padding(.bottom, 8)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if let error = errorMessage {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Retry") { checkText() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }

            Spacer()

            if isLoading {
                Button("Cancel") { checkTask?.cancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Button("Check") { checkText() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Logic

    private func checkText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        correctedText = ""
        checkTask?.cancel()

        checkTask = Task { @MainActor in
            defer { if !Task.isCancelled { isLoading = false } }
            do {
                let bundleID = await AccessibilityBridge.shared.frontAppBundleID()
                let prefs = PreferencesStore.shared
                let resolved = RuleResolver.resolve(
                    appBundleID: bundleID,
                    customPrompts: prefs.customPrompts,
                    appRules: prefs.appRules
                )
                let type: PromptType = checkMode == .fluency ? .fluency : .grammar
                let serviceType: ServiceType? = checkMode == .fluency
                    ? (resolved.serviceType ?? LLMServiceFactory.resolveFluencyServiceType())
                    : resolved.serviceType
                let result = try await RequestQueue.shared.enqueue(
                    text: text,
                    type: type,
                    priority: .floatingEditor,
                    overrideServiceType: serviceType,
                    overrideCustomPrompt: resolved.prompt
                )
                guard !Task.isCancelled else { return }
                correctedText = result.correctedText
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
