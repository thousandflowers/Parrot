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
            if !reduceMotion, existing.alphaValue < 1.0 {
                fadeIn(existing)
            }
            return
        }

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "RefineClone - Editor"
        newWindow.level = .floating
        newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newWindow.isReleasedWhenClosed = false
        newWindow.center()

        let hostingView = NSHostingView(rootView: FloatingEditorView(onDismiss: { [weak self] in
            self?.close()
        }))

        newWindow.contentView = hostingView
        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        fadeIn(newWindow)
    }

    private func fadeIn(_ window: NSWindow) {
        guard !reduceMotion else { return }
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
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
        case grammar = "Grammatica"
        case fluency = "Fluidità"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $checkMode) {
                    ForEach(CheckMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            HSplitView {
                VStack {
                    Text("Originale")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)

                    TextEditor(text: $inputText)
                        .font(.body)
                        .accessibilityLabel("Editor di testo")
                        .frame(minWidth: 250, minHeight: 200)
                        .scrollContentBackground(.hidden)
                        .background(Color(.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.tertiary, lineWidth: 0.5)
                        )
                        .cornerRadius(4)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }

                VStack {
                    Text("Corretto")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)

                    ScrollView {
                        Text(correctedText)
                            .font(.body)
                            .textSelection(.enabled)
                            .accessibilityLabel("Testo corretto")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minWidth: 250, minHeight: 200)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(4)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }

            wordCountFooter

            Divider()

            HStack {
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.statusError)
                        .font(.caption)
                    Button("Riprova") { checkText() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .accessibilityLabel("Riprova controllo")
                        .accessibilityHint("Riesegue il controllo grammaticale")
                    Button("Usa Stub") { checkWithStub() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .font(.caption)
                        .accessibilityLabel("Usa servizio stub")
                        .accessibilityHint("Esegue il controllo con il servizio di test locale")
                }
                Spacer()

                Button("Controlla") { checkText() }
                    .buttonStyle(.borderedProminent)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    .accessibilityLabel("Controlla testo")
                    .accessibilityHint("Avvia il controllo grammaticale sul testo inserito")

                Button("Copia") {
                    NSPasteboard.general.clearContents()
                    let item = NSPasteboardItem()
                    item.setString(correctedText, forType: .string)
                    NSPasteboard.general.writeObjects([item])
                }
                .disabled(correctedText.isEmpty)
                .accessibilityLabel("Copia testo corretto")
                .accessibilityHint("Copia il testo corretto negli appunti")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if isLoading {
                ProgressView("Controllando...")
                    .padding(.bottom, 8)
            }
        }
        .frame(minWidth: 500, minHeight: 300)
        .onDisappear {
            checkTask?.cancel()
        }
    }

    private var wordCountFooter: some View {
        let wc = inputText.split(separator: " ").count
        let cc = inputText.count
        return HStack(spacing: 16) {
            Label("\(wc) parole", systemImage: "text.word.spacing")
            Label("\(cc) caratteri", systemImage: "character.cursor.ibeam")
        }
        .font(.caption2)
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func checkText() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isLoading = true
        errorMessage = nil
        correctedText = ""
        checkTask?.cancel()
        checkTask = Task { @MainActor in
            defer {
                if !Task.isCancelled { self.isLoading = false }
            }
            do {
                let bundleID = await AccessibilityBridge.shared.frontAppBundleID()
                let prefs = PreferencesStore.shared
                let resolved = RuleResolver.resolve(
                    appBundleID: bundleID,
                    customPrompts: prefs.customPrompts,
                    appRules: prefs.appRules
                )

                if checkMode == .fluency {
                    let fluencyType = resolved.serviceType ?? LLMServiceFactory.resolveFluencyServiceType()
                    let result = try await RequestQueue.shared.enqueue(
                        text: inputText,
                        type: .fluency,
                        priority: .floatingEditor,
                        overrideServiceType: fluencyType,
                        overrideCustomPrompt: resolved.prompt
                    )
                    guard !Task.isCancelled else { return }
                    self.correctedText = result.correctedText
                } else {
                    let result = try await RequestQueue.shared.enqueue(
                        text: inputText,
                        type: .grammar,
                        priority: .floatingEditor,
                        overrideServiceType: resolved.serviceType,
                        overrideCustomPrompt: resolved.prompt
                    )
                    guard !Task.isCancelled else { return }
                    self.correctedText = result.correctedText
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = "Errore: \(error.localizedDescription)"
            }
        }
    }

    private func checkWithStub() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isLoading = true
        errorMessage = nil
        correctedText = ""
        checkTask?.cancel()
        checkTask = Task { @MainActor in
            defer {
                if !Task.isCancelled { self.isLoading = false }
            }
            do {
                let result = try await RequestQueue.shared.enqueue(
                    text: inputText,
                    type: checkMode == .fluency ? .fluency : .grammar,
                    priority: .floatingEditor,
                    overrideServiceType: .stub
                )
                guard !Task.isCancelled else { return }
                self.correctedText = result.correctedText
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = "Errore: \(error.localizedDescription)"
            }
        }
    }
}
