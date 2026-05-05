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
        newWindow.makeKeyAndOrderFront(nil)
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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Inserisci o incolla il testo da correggere")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            HSplitView {
                VStack {
                    Text("Originale")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)

                    TextEditor(text: $inputText)
                        .font(.body)
                        .frame(minWidth: 250, minHeight: 200)
                        .border(Color.secondary.opacity(0.3))
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minWidth: 250, minHeight: 200)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(4)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }

            Divider()

            HStack {
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                Spacer()

                Button("Controlla") { checkText() }
                    .buttonStyle(.borderedProminent)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)

                Button("Copia") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(correctedText, forType: .string)
                }
                .disabled(correctedText.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if isLoading {
                ProgressView("Controllando...")
                    .padding(.bottom, 8)
            }
        }
        .frame(minWidth: 500, minHeight: 300)
    }

    private func checkText() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isLoading = true
        errorMessage = nil
        correctedText = ""

        Task {
            do {
                let result = try await RequestQueue.shared.enqueue(
                    text: inputText,
                    type: .grammar,
                    priority: .floatingEditor
                )
                self.correctedText = result.correctedText
                self.isLoading = false
            } catch {
                self.errorMessage = "Errore: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
}
