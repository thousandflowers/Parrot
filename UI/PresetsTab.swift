import SwiftUI

struct PresetsTab: View {
    @Bindable var prefs: PreferencesStore
    @State private var editingPreset: Preset?
    @State private var showingAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            if prefs.presets.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "star.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.accentColor.opacity(0.5))
                        .accessibilityHidden(true)
                    Text("No saved presets")
                        .font(.headline)
                    Text("Save your favorite combinations of template, language and model for quick reuse.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(prefs.presets) { preset in
                        HStack(spacing: 10) {
                            Image(systemName: preset.icon)
                                .foregroundColor(.accentColor)
                                .frame(width: 20)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(preset.name).font(.headline)
                                    if let key = preset.shortcutKey {
                                        Text("Cmd+Shift+\(key)")
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.quaternary)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                                Text("\(preset.language.uppercased()) · \(preset.serviceType?.rawValue ?? "default")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Edit") { editingPreset = preset }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        let toDelete = indexSet.map { prefs.presets[$0] }
                        for p in toDelete { prefs.deletePreset(p) }
                    }
                }
            }

            Divider()

            HStack {
                Text("Presets save language, temperature and model")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("New preset") { showingAddSheet = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showingAddSheet) {
            PresetEditSheet(prefs: prefs, preset: nil)
        }
        .sheet(item: $editingPreset) { preset in
            PresetEditSheet(prefs: prefs, preset: preset)
        }
    }
}

struct PresetEditSheet: View {
    let prefs: PreferencesStore
    let preset: Preset?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Bool

    @State private var name: String
    @State private var template: String
    @State private var language: String
    @State private var temperature: Double
    @State private var icon: String
    @State private var shortcutKey: String

    init(prefs: PreferencesStore, preset: Preset?) {
        self.prefs = prefs
        self.preset = preset
        _name = State(initialValue: preset?.name ?? "")
        _template = State(initialValue: preset?.template ?? "")
        _language = State(initialValue: preset?.language ?? "it")
        _temperature = State(initialValue: preset?.temperature ?? 0.1)
        _icon = State(initialValue: preset?.icon ?? "star")
        _shortcutKey = State(initialValue: preset?.shortcutKey ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(preset == nil ? "New Preset" : "Edit Preset")
                .font(.title2.bold())

            TextField("Preset name", text: $name)
                .focused($focusedField)
            TextField("Template (use {{TEXT}} for the text)", text: $template, axis: .vertical)
                .lineLimit(4...8)

            HStack {
                Picker("Language", selection: $language) {
                    Text("Italiano").tag("it")
                    Text("English (US)").tag("en-US")
                    Text("Français").tag("fr")
                    Text("Español").tag("es")
                    Text("Deutsch").tag("de")
                }
                Slider(value: $temperature, in: 0.0...1.0, step: 0.05) {
                    Text("Temp: \(temperature, specifier: "%.2f")")
                }
            }

            TextField("SF Symbol icon (e.g. star, wand.and.stars)", text: $icon)
            TextField("Shortcut key (e.g. 1, 2, 3)", text: $shortcutKey)
                .help("Cmd+Shift+[key] to activate the preset")

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(preset == nil ? "Create" : "Save") {
                    let p = Preset(
                        id: preset?.id ?? UUID(),
                        name: name, template: template,
                        language: language, temperature: temperature,
                        icon: icon.isEmpty ? "star" : icon,
                        shortcutKey: shortcutKey.isEmpty ? nil : shortcutKey
                    )
                    if preset == nil {
                        prefs.addPreset(p)
                    } else {
                        prefs.updatePreset(p)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || template.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 450)
        .onAppear { focusedField = true }
    }
}

#Preview {
    PresetsTab(prefs: PreferencesStore.shared)
}

#Preview {
    PresetEditSheet(prefs: PreferencesStore.shared, preset: nil)
}
