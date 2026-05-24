import Foundation
import OSLog

struct ContactProfile: Identifiable, Codable, Sendable, Hashable {
    var id: UUID
    var name: String
    var role: String           // "professore di informatica", "collega", "amico"
    var formality: Formality
    var salutation: String     // "Gentile Professore Rossi"
    var closing: String        // "Cordiali saluti"
    var notes: String          // "preferisce email brevi"
    var lastSeen: Date

    enum Formality: String, Codable, Sendable, CaseIterable {
        case formal     = "formale"
        case semiformal = "semi-formale"
        case informal   = "informale"
    }

    init(id: UUID = UUID(), name: String, role: String = "",
         formality: Formality = .semiformal, salutation: String = "",
         closing: String = "Cordiali saluti", notes: String = "", lastSeen: Date = Date()) {
        self.id = id
        self.name = name
        self.role = role
        self.formality = formality
        self.salutation = salutation.isEmpty ? "Gentile \(name)" : salutation
        self.closing = closing
        self.notes = notes
        self.lastSeen = lastSeen
    }
}

actor ContactStore {
    static let shared = ContactStore(persistent: true)
    private let logger = Logger(subsystem: Constants.bundleID, category: "ContactStore")
    private var contacts: [ContactProfile] = []
    private let fileURL: URL?

    private static func makeFileURL() -> URL {
        let dir = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("Parrot")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("contacts.json")
    }

    /// Pass `persistent: true` for the app singleton; omit for in-memory test instances.
    init(persistent: Bool = false) {
        if persistent {
            let url = Self.makeFileURL()
            fileURL = url
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([ContactProfile].self, from: data) {
                contacts = decoded
            }
        } else {
            fileURL = nil
        }
    }

    var all: [ContactProfile] { contacts }

    /// Finds a known contact whose name or role appears anywhere in `text`.
    func findInText(_ text: String) -> ContactProfile? {
        let lower = text.lowercased()
        return contacts
            .filter { c in
                let name = c.name.lowercased()
                let role = c.role.lowercased()
                return (!name.isEmpty && lower.contains(name)) ||
                       (!role.isEmpty && lower.contains(role))
            }
            .sorted { $0.lastSeen > $1.lastSeen }
            .first
    }

    func upsert(_ profile: ContactProfile) {
        if let i = contacts.firstIndex(where: { $0.id == profile.id }) {
            contacts[i] = profile
        } else {
            contacts.append(profile)
        }
        persist()
    }

    func delete(id: UUID) {
        contacts.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        guard let url = fileURL, let data = try? JSONEncoder().encode(contacts) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
