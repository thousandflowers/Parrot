import SwiftUI
import Cocoa

@MainActor
final class FloatingEditorController {
    static let shared = FloatingEditorController()

    private var window: NSWindow?

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
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
        newWindow.alphaValue = 0
        newWindow.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            newWindow.animator().alphaValue = 1
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
                Text("Servizio: \(LLMServiceFactory.resolveDefaultServiceType().rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            HSplitView {
                VStack {
                    Text("Originale")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    TextEditor(text: $inputText)
                        .font(.body)
                        .frame(minWidth: 250, minHeight: 200)
                        .accessibilityLabel("Testo originale da correggere")
                        .border(Color.secondary.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }

                VStack {
                    Text("Corretto")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    ScrollView {
                        if correctedText.isEmpty {
                            Text("Il testo corretto apparirà qui")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            DiffHighlightView(original: inputText, corrected: correctedText)
                                .font(.body)
                                .textSelection(.enabled)
                                .accessibilityLabel("Testo corretto con differenze evidenziate")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(minWidth: 250, minHeight: 200)
                    .background(Color(.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }

            Divider()

            HStack {
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.refineError)
                        .font(.caption)
                }
                Spacer()

                Button(action: { checkText() }) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 16)
                        Text("Controllando…")
                    } else {
                        Text("Controlla")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)

                Button("Copia") {
                    NSPasteboard.general.clearContents()
                    let item = NSPasteboardItem()
                    item.setString(correctedText, forType: .string)
                    NSPasteboard.general.writeObjects([item])
                }
                .disabled(correctedText.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 500, minHeight: 300)
        .onDisappear {
            checkTask?.cancel()
        }
    }

    private func checkText() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isLoading = true
        errorMessage = nil
        correctedText = ""
        checkTask?.cancel()
        checkTask = Task { @MainActor in
            defer { if !Task.isCancelled { self.isLoading = false } }
            do {
                let bundleID = await AccessibilityBridge.shared.frontAppBundleID()
                let prefs = PreferencesStore.shared
                let resolved = RuleResolver.resolve(
                    appBundleID: bundleID,
                    customPrompts: prefs.customPrompts,
                    appRules: prefs.appRules
                )

                let serviceType: ServiceType
                let basePrompt: PromptType
                if checkMode == .fluency {
                    serviceType = resolved.serviceType ?? LLMServiceFactory.resolveFluencyServiceType()
                    basePrompt = .fluency
                } else {
                    serviceType = resolved.serviceType ?? LLMServiceFactory.resolveDefaultServiceType()
                    basePrompt = .grammar
                }
                let promptType: PromptType = resolved.prompt.map {
                    .custom(name: $0.name, template: $0.template)
                } ?? basePrompt

                let service = LLMServiceFactory.make(with: serviceType)
                let stream = service.streamCorrect(text: inputText, promptType: promptType)
                for try await accumulated in stream {
                    guard !Task.isCancelled else { return }
                    // streamCorrect yields cumulative text — replace, don't append
                    correctedText = accumulated.trimmingCharacters(in: .init(charactersIn: " \n\t"))
                }
                correctedText = correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                guard !Task.isCancelled else { return }
                if let corrErr = error as? CorrectionError, case .serverNotRunning = corrErr {
                    let hint: String
                    switch LLMServiceFactory.resolveDefaultServiceType() {
                    case .local:
                        hint = "llama-server non trovato. Vai nel tab Modelli per installarlo, oppure cambia servizio."
                    case .ollama:
                        hint = "Ollama offline. Avvia 'ollama serve' nel terminale, oppure cambia servizio."
                    default:
                        hint = error.localizedDescription
                    }
                    self.errorMessage = "Errore: \(hint)"
                } else {
                    self.errorMessage = "Errore: \(error.localizedDescription)"
                }
            }
        }
    }
}
