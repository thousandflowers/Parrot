import Foundation

struct AppRule: Identifiable, Codable, Sendable {
    let id: UUID
    var bundleID: String
    var displayName: String
    var promptID: UUID?
    var serviceType: ServiceType?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        bundleID: String,
        displayName: String,
        promptID: UUID? = nil,
        serviceType: ServiceType? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.bundleID = bundleID
        self.displayName = displayName
        self.promptID = promptID
        self.serviceType = serviceType
        self.isEnabled = isEnabled
    }
}
