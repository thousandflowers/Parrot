import Foundation

struct Preset: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var template: String
    var language: String
    var temperature: Double
    var modelID: String?
    var serviceType: ServiceType?
    var icon: String
    var shortcutKey: String?

    init(id: UUID = UUID(), name: String, template: String, language: String = "it",
         temperature: Double = 0.1, modelID: String? = nil, serviceType: ServiceType? = nil,
         icon: String = "star", shortcutKey: String? = nil) {
        self.id = id
        self.name = name
        self.template = template
        self.language = language
        self.temperature = temperature
        self.modelID = modelID
        self.serviceType = serviceType
        self.icon = icon
        self.shortcutKey = shortcutKey
    }
}
