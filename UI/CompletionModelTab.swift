import SwiftUI

/// Wren's model picker: choose which local .gguf drives inline completion.
/// Setting `selectedModelID` is enough — the completion helper reloads the model
/// on the next keystroke (see HelperCompletionProvider.ensureHelper). Bigger
/// instruction/base models (e.g. gemma-3-4b) give markedly better suggestions
/// than the tiny bundled default.
struct CompletionModelTab: View {
    @Bindable var prefs: PreferencesStore
    @State private var models: [DiscoveredModel] = []
    @State private var loading = true

    var body: some View {
        Form {
            Section {
                if loading {
                    HStack { ProgressView().controlSize(.small); Text("Scanning models…") }
                } else if models.isEmpty {
                    Text("No models found. Add a .gguf file to your Models folder, then reopen this tab.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(models) { model in
                        Button {
                            prefs.selectedModelID = model.id
                        } label: {
                            HStack {
                                Image(systemName: Self.isActive(modelID: model.id, selected: prefs.selectedModelID)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Self.isActive(modelID: model.id, selected: prefs.selectedModelID)
                                                     ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(model.name).foregroundStyle(.primary)
                                    Text(Self.sizeString(model.size))
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Label("Completion model", systemImage: "cpu")
            } footer: {
                Text("The model that powers inline suggestions. Larger models (e.g. gemma-3-4b) suggest better but use more RAM. Changing it reloads on your next keystroke.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await load() }
    }

    private func load() async {
        models = await ModelManager.shared.localModels()
        loading = false
    }

    // MARK: - Pure helpers (testable)

    /// True when `modelID` is the selected completion model, ignoring a trailing
    /// ".gguf" and case differences.
    static func isActive(modelID: String, selected: String) -> Bool {
        guard !selected.isEmpty else { return false }
        func norm(_ s: String) -> String {
            (s.hasSuffix(".gguf") ? String(s.dropLast(5)) : s).lowercased()
        }
        return norm(modelID) == norm(selected)
    }

    static func sizeString(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}
