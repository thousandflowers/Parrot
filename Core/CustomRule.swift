import Foundation

struct CustomRule: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var pattern: String
    var replacement: String
    var isEnabled: Bool
    var isRegex: Bool
    var isCaseSensitive: Bool
    var supportsBackreferences: Bool
    var language: String

    init(
        id: UUID = UUID(),
        name: String = "",
        pattern: String = "",
        replacement: String = "",
        isEnabled: Bool = true,
        isRegex: Bool = false,
        isCaseSensitive: Bool = false,
        supportsBackreferences: Bool = false,
        language: String = "any"
    ) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.replacement = replacement
        self.isEnabled = isEnabled
        self.isRegex = isRegex
        self.isCaseSensitive = isCaseSensitive
        self.supportsBackreferences = supportsBackreferences
        self.language = language
    }
}
