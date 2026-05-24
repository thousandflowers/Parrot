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
    static let shared = ContactStore()
    private let logger = Logger(subsystem: Constants.bundleID, category: "ContactStore")
    private var contacts: [ContactProfile] = []

    private static var fileURL: URL {
        let dir = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("Parrot")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("contacts.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode([ContactProfile].self, from: data) {
            contacts = decoded
        }
    }

    var all: [ContactProfile] { contacts }

    func find(recipient: String?) -> ContactProfile? {
        guard let r = recipient?.lowercased(), !r.isEmpty else { return nil }
        return contacts.first { c in
            c.name.lowercased().contains(r) || r.contains(c.name.lowercased()) ||
            c.role.lowercased().contains(r) || r.contains(c.role.lowercased())
        }
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
        guard let data = try? JSONEncoder().encode(contacts) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
