import SwiftUI

struct ExportImportTab: View {
    private static let isoFormatter = ISO8601DateFormatter()

    @State private var selectedSections: Set<String> = []
    @State private var showFilePicker = false
    @State private var exportMessage: String?
    @State private var importMessage: String?
    @State private var importedSections: [String] = []

    private let sections = ExportImportManager.availableSections

    var body: some View {
        Form {
            Section {
                ForEach(sections) { section in
                    Toggle(isOn: Binding(
                        get: { selectedSections.contains(section.id) },
                        set: { isSelected in
                            if isSelected { selectedSections.insert(section.id) }
                            else { selectedSections.remove(section.id) }
                        }
                    )) {
                        Label(section.label, systemImage: section.icon)
                    }
                }
            } header: {
                Text("Select what to include")
            } footer: {
                Text("\(selectedSections.count) of \(sections.count) sections selected")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 16) {
                    Button(action: exportConfig) {
                        Label("Export JSON", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedSections.isEmpty)

                    Button(action: { showFilePicker = true }) {
                        Label("Import JSON", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)

                Group {
                    if let exportMessage {
                        Label(exportMessage, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.statusOk)
                            .accessibilityLabel(exportMessage)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if let importMessage {
                        Label(importMessage, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.statusOk)
                            .accessibilityLabel(importMessage)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if !importedSections.isEmpty {
                        Text("Imported: \(importedSections.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: exportMessage != nil || importMessage != nil || !importedSections.isEmpty)
            } header: {
                Text("Actions")
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importConfig(from: url)
            case .failure(let error):
                importMessage = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    private func exportConfig() {
        do {
            let data = try ExportImportManager.shared.export(selectedSections: selectedSections)
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.json]
                savePanel.nameFieldStringValue = "parrot-config-\(Self.isoFormatter.string(from: Date())).json"
                savePanel.title = "Export Parrot Configuration"

                guard case .OK = savePanel.runModal(), let url = savePanel.url else { return }
                try data.write(to: url)
                exportMessage = "Exported \(selectedSections.count) sections"
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    await MainActor.run { exportMessage = nil }
                }
            } catch {
                exportMessage = "Export failed: \(error.localizedDescription)"
            }
    }

    private func importConfig(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let imported = try ExportImportManager.shared.importData(from: data)
            importedSections = imported
            importMessage = "Imported \(imported.count) sections"
            Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await MainActor.run { importMessage = nil }
            }
        } catch {
            importMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ExportImportTab()
}
