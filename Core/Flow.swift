import Foundation

struct Flow: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var icon: String
    var steps: [Step]

    struct Step: Codable, Sendable, Hashable {
        var promptType: PromptType
        var customInstruction: String?

        enum CodingKeys: CodingKey {
            case promptType, customInstruction
        }

        init(promptType: PromptType, customInstruction: String? = nil) {
            self.promptType = promptType
            self.customInstruction = customInstruction
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.promptType = try container.decode(PromptType.self, forKey: .promptType)
            self.customInstruction = try container.decodeIfPresent(String.self, forKey: .customInstruction)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(promptType, forKey: .promptType)
            try container.encodeIfPresent(customInstruction, forKey: .customInstruction)
        }
    }

    enum CodingKeys: CodingKey {
        case id, name, icon, steps
    }

    init(id: UUID = UUID(), name: String, icon: String = "arrow.triangle.2.circlepath", steps: [Step]) {
        self.id = id
        self.name = name
        self.icon = icon
        self.steps = steps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "arrow.triangle.2.circlepath"
        self.steps = try container.decode([Step].self, forKey: .steps)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(icon, forKey: .icon)
        try container.encode(steps, forKey: .steps)
    }
}
