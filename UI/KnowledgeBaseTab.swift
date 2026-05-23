import SwiftUI

struct KnowledgeBaseTab: View {
    @State private var documents: [KnowledgeDocument] = []
    @State private var showAddSnippet = false
    @State private var newTitle = ""
    @State private var newContent = ""
    @State private var importMessage: String?

    var body: some View {
        Form {
            Section {
                Group {
                    if documents.isEmpty {
                        Text("No documents yet. Add files, snippets, or enable auto-learning from corrections.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                            .transition(.opacity)
                    } else {
                        ForEach(documents) { doc in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(doc.title)
                                        .font(.subheadline.weight(.medium))
                                    Text(doc.source.label)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    Task { await KnowledgeBase.shared.removeDocument(id: doc.id) }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Delete \(doc.title)")
                            }
                            .transition(.opacity.combined(with: .slide))
                        }
                    }
                }
                .animation(.easeOut(duration: 0.2), value: documents.isEmpty)
            } header: {
                Text("Documents (\(documents.count))")
            }

            Section {
                Button("Add snippet…") { showAddSnippet = true }
                    .frame(maxWidth: .infinity)

                Button("Import files…") { importFiles() }
                    .frame(maxWidth: .infinity)

                Group {
                    if let importMessage {
                        Label(importMessage, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                        .foregroundStyle(Color.statusOk)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.easeOut(duration: 0.2), value: importMessage != nil)
            } header: {
                Text("Add content")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showAddSnippet) {
            AddSnippetSheet(title: $newTitle, content: $newContent) {
                Task {
                    await KnowledgeBase.shared.addDocument(title: newTitle, content: newContent, source: .snippet)
                    guard !Task.isCancelled else { return }
                    newTitle = ""
                    newContent = ""
                }
            }
        }
        .task {
            documents = await KnowledgeBase.shared.allDocuments
        }

    }

    private func importFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .utf8PlainText, .utf16PlainText, .rtf]
        panel.allowsMultipleSelection = true

        guard case .OK = panel.runModal() else { return }

        for url in panel.urls {
            guard let content = try? String(contentsOf: url) else { continue }
            let title = url.lastPathComponent
            Task {
                await KnowledgeBase.shared.addDocument(title: title, content: content, source: .file)
                guard !Task.isCancelled else { return }
                importMessage = "Imported \(panel.urls.count) files"
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                importMessage = nil
            }
        }
    }
}

extension KnowledgeDocument.Source {
    var label: String {
        switch self {
        case .file: "File"
        case .snippet: "Snippet"
        case .autoLearned: "Auto-learned"
        }
    }
}

private struct AddSnippetSheet: View {
    @Binding var title: String
    @Binding var content: String
    @FocusState private var focusedField: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField)
            TextEditor(text: $content)
                .frame(minHeight: 120)
                .border(.separator, width: 0.5)
                .accessibilityLabel("Snippet content")
            HStack {
                Button("Cancel") { title = ""; content = "" }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Add") { onSave() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear { focusedField = true }
    }
}

#Preview {
    KnowledgeBaseTab()
}

#Preview {
    AddSnippetSheet(title: .constant(""), content: .constant(""), onSave: {})
}
