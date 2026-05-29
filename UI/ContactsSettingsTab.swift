import SwiftUI

struct ContactsSettingsTab: View {
    @State private var contacts: [ContactProfile] = []
    @State private var selectedID: UUID?
    @State private var editingContact: ContactProfile?
    @State private var showAddSheet = false

    var body: some View {
        HSplitView {
            contactList
                .frame(minWidth: 180, maxWidth: 240)
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { reload() }
        .sheet(isPresented: $showAddSheet) {
            ContactEditSheet(contact: ContactProfile(name: ""), onSave: { profile in
                Task { await ContactStore.shared.upsert(profile); reload() }
                showAddSheet = false
            }, onCancel: { showAddSheet = false })
        }
    }

    private var contactList: some View {
        VStack(spacing: 0) {
            List(selection: $selectedID) {
                ForEach(contacts) { contact in
                    Text(contact.name)
                        .tag(contact.id)
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add contact")
                Button {
                    if let id = selectedID {
                        Task { await ContactStore.shared.delete(id: id); reload() }
                        selectedID = nil
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selectedID == nil)
                .accessibilityLabel("Delete contact")
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let id = selectedID, let contact = contacts.first(where: { $0.id == id }) {
            ContactDetailView(contact: contact) { updated in
                Task { await ContactStore.shared.upsert(updated); reload() }
            }
        } else {
            Text("Seleziona un contatto")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func reload() {
        Task {
            let all = await ContactStore.shared.all
            await MainActor.run { contacts = all.sorted { $0.name < $1.name } }
        }
    }
}

private struct ContactDetailView: View {
    var contact: ContactProfile
    var onSave: (ContactProfile) -> Void

    @State private var draft: ContactProfile

    init(contact: ContactProfile, onSave: @escaping (ContactProfile) -> Void) {
        self.contact = contact
        self.onSave = onSave
        _draft = State(initialValue: contact)
    }

    var body: some View {
        Form {
            Section("Identità") {
                TextField("Nome", text: $draft.name)
                    .accessibilityLabel("Name")
                TextField("Ruolo (es. professore, collega)", text: $draft.role)
                    .accessibilityLabel("Role")
                Picker("Formalità", selection: $draft.formality) {
                    ForEach(ContactProfile.Formality.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Messaggio") {
                TextField("Saluto (es. Gentile Professore Rossi)", text: $draft.salutation)
                    .accessibilityLabel("Salutation")
                TextField("Chiusura (es. Cordiali saluti)", text: $draft.closing)
                    .accessibilityLabel("Closing")
            }

            Section("Note") {
                TextEditor(text: $draft.notes)
                    .frame(minHeight: 60, maxHeight: 120)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: draft) { _, new in onSave(new) }
    }
}

private struct ContactEditSheet: View {
    @State var contact: ContactProfile
    var onSave: (ContactProfile) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Nuovo contatto")
                .font(.headline)
                .padding()
            Divider()
            Form {
                TextField("Nome *", text: $contact.name)
                    .accessibilityLabel("Name")
                TextField("Ruolo", text: $contact.role)
                    .accessibilityLabel("Role")
                Picker("Formalità", selection: $contact.formality) {
                    ForEach(ContactProfile.Formality.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                TextField("Saluto", text: $contact.salutation)
                    .accessibilityLabel("Salutation")
                TextField("Chiusura", text: $contact.closing)
                    .accessibilityLabel("Closing")
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Annulla") { onCancel() }
                    .accessibilityLabel("Cancel")
                Spacer()
                Button("Salva") { onSave(contact) }
                    .disabled(contact.name.isEmpty)
                    .keyboardShortcut(.return)
                    .accessibilityLabel("Save")
            }
            .padding()
        }
        .frame(width: 380, height: 380)
    }
}
