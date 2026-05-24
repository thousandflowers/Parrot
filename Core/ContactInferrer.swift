import Foundation

/// Extracts contact info from an expanded message via a single LLM call.
/// No keyword lists — the model handles all language-specific understanding.
enum ContactInferrer {
    struct InferredContact {
        var name: String?
        var role: String?
        var formality: ContactProfile.Formality
        var salutation: String?
        var closing: String?
    }

    private static let extractionTemplate = """
    Extract contact information from the message below. \
    Respond ONLY with a single valid JSON object — no explanation, no markdown.
    Schema: {"name":string|null,"role":string|null,"formality":"formal"|"semiformal"|"informal","salutation":string|null,"closing":string|null}
    Rules:
    - name: recipient's name if stated, else null
    - role: their role/title in plain language (e.g. "professor", "colleague", "manager"), else null
    - formality: infer from vocabulary and register of the message
    - salutation: the opening greeting line verbatim, else null
    - closing: the farewell/sign-off line verbatim, else null
    <MESSAGE>{{TEXT}}</MESSAGE>
    """

    static func extract(from expandedText: String) async -> InferredContact? {
        guard let result = try? await RequestQueue.shared.enqueue(
            text: expandedText,
            type: .custom(name: "ContactExtract", template: extractionTemplate),
            priority: .autoCheck,
            language: ""
        ) else { return nil }

        return parse(result.correctedText)
    }

    private static func parse(_ raw: String) -> InferredContact? {
        // Strip optional markdown fences the model might add
        var json = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```") {
            json = json.components(separatedBy: "\n").dropFirst().dropLast().joined(separator: "\n")
        }
        guard let data = json.data(using: .utf8),
              let obj = try? JSONDecoder().decode(ContactJSON.self, from: data) else { return nil }

        let formality: ContactProfile.Formality
        switch obj.formality?.lowercased() {
        case "formal":     formality = .formal
        case "informal":   formality = .informal
        default:           formality = .semiformal
        }
        return InferredContact(
            name: obj.name.flatMap { $0.isEmpty ? nil : $0 },
            role: obj.role.flatMap { $0.isEmpty ? nil : $0 },
            formality: formality,
            salutation: obj.salutation.flatMap { $0.isEmpty ? nil : $0 },
            closing: obj.closing.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private struct ContactJSON: Decodable {
        let name: String?
        let role: String?
        let formality: String?
        let salutation: String?
        let closing: String?
    }
}
