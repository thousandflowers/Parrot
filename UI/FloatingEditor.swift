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
        newWindow.title = "Editor — Parrot"
        newWindow.subtitle = "Correct and improve your text"
        newWindow.level = .floating
        newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.setFrameAutosaveName("FloatingEditorWindow")

        newWindow.contentView = FixedSizeHostingView(rootView: FloatingEditorView(onDismiss: { [weak self] in
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
    @State private var showDiff: Bool = true
    @StateObject private var dictation = DictationService()
    @State private var analysisResult: StoryAnalysisResult?
    @State private var isAnalyzing = false
    @State private var showAnalysis = false
    @State private var recordingPulse = false

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
        .sheet(isPresented: $showAnalysis) {
            if let result = analysisResult {
                StoryAnalysisSheet(result: result)
            }
        }
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
            .accessibilityLabel("Check mode")

            Spacer()

            if isLoading {
                ProgressView().scaleEffect(0.7).frame(width: 16, height: 16)
                Text("Processing…")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            if dictation.authorizationStatus == .authorized {
            Button {
                if dictation.isListening {
                    dictation.stopListening()
                    if !dictation.transcribedText.isEmpty {
                        inputText = dictation.transcribedText
                    }
                } else {
                    dictation.startListening()
                }
            } label: {
                Image(systemName: dictation.isListening ? "mic.fill" : "mic")
                    .font(.system(size: 14))
                    .foregroundStyle(dictation.isListening ? Color.statusError : .secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .help(dictation.isListening ? "Stop dictation" : "Start dictation")
            .accessibilityLabel(dictation.isListening ? "Stop dictation" : "Start dictation")

            Button {
                importFile()
            } label: {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .help("Import file")
            .accessibilityLabel("Import file")

            if inputText.split(separator: " ").count > 100 {
                Button {
                    analyzeStory()
                } label: {
                    Image(systemName: "book")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .help("Analyze story/manuscript")
                .accessibilityLabel("Analyze story")
            }
            } else {
                Button {
                    dictation.requestAuthorization()
                } label: {
                    Image(systemName: "mic.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .help("Enable dictation")
                .accessibilityLabel("Enable dictation")
            }

            wordCountBadge
        }
        .animation(.easeOut(duration: 0.18), value: isLoading)
        .animation(.easeOut(duration: 0.2), value: inputText.isEmpty)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.surfaceBackground)
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
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
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
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            TextEditor(text: $inputText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .background(.clear)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .accessibilityLabel("Text to analyze")

            if dictation.isListening {
                Divider()
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.statusError)
                        .frame(width: 6, height: 6)
                        .opacity(recordingPulse ? 1 : 0.4)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: recordingPulse)
                        .onAppear { recordingPulse = true }
                        .onDisappear { recordingPulse = false }
                    Text(dictation.transcribedText)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.surfaceElevated)
            }
        }
        .frame(minWidth: 240)
        .background(Color.surfaceBackground)
    }

    private var outputPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Corrected")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)

                Spacer()

                if !correctedText.isEmpty {
                    // Diff / Result toggle
                    HStack(spacing: 4) {
                        Image(systemName: showDiff ? "highlighter" : "doc.text")
                            .font(.caption2)
                            .foregroundStyle(Color.textSecondary)
                        Toggle(showDiff ? "Changes" : "Result", isOn: $showDiff)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                            .accessibilityLabel("Show changes")
                    }
                    .help(showDiff ? "Showing changes — toggle to see clean result" : "Showing result — toggle to see changes")

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(correctedText, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.textSecondary)
                    .help("Copy corrected text")
                    .accessibilityLabel("Copy corrected text")
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
                        .transition(.opacity)
                } else if showDiff {
                    DiffHighlightView(
                        original: inputText,
                        corrected: correctedText.isEmpty ? inputText : correctedText
                    )
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    Text(correctedText.isEmpty ? inputText : correctedText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .textSelection(.enabled)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeOut(duration: 0.22), value: correctedText.isEmpty)
            .animation(.easeOut(duration: 0.15), value: showDiff)
            .frame(minWidth: 240)
            .padding(.bottom, 8)
        }
        .background(Color.surfaceElevated)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if let error = errorMessage {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Color.statusError)
                    .font(.caption)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                Button("Retry") { checkText() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .accessibilityLabel("Retry")
                Button("Use Stub") {
                    Task { @MainActor in
                        PreferencesStore.shared.serviceType = .stub
                        checkText()
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("Switch to stub service and retry")
            }

            Spacer()

            if isLoading {
                Button("Cancel") { checkTask?.cancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .accessibilityLabel("Cancel")
            } else {
                Button("Check") { checkText() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .accessibilityLabel("Check")
            }
        }
        .animation(.easeOut(duration: 0.18), value: isLoading)
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
            defer { isLoading = false }
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

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .utf8PlainText, .utf16PlainText, .rtf, .text]
        panel.allowsMultipleSelection = false

        guard case .OK = panel.runModal(), let url = panel.url else { return }
        guard let content = try? String(contentsOf: url) else { return }
        inputText = content
    }

    private func analyzeStory() {
        guard !inputText.isEmpty else { return }
        isAnalyzing = true
        errorMessage = nil

        Task { @MainActor in
            do {
                analysisResult = try await StoryAnalyzer.shared.analyze(text: inputText)
                guard !Task.isCancelled else { return }
                showAnalysis = true
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            guard !Task.isCancelled else { return }
            isAnalyzing = false
        }
    }
}
