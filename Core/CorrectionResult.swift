import Foundation

struct CorrectionResult: Identifiable, Codable, Sendable {
    let id: UUID
    let originalText: String
    let correctedText: String
    let explanation: String?
    let confidence: Double?
    let diffOperations: [DiffOp]?
    let timestamp: Date
    let modelID: String
    let customInstruction: String?
    let promptType: String

    struct DiffOp: Codable, Sendable {
        enum OpType: String, Codable {
            case insert
            case delete
            case replace
            case keep
        }
        let type: OpType
        let offset: Int
        let length: Int
        let replacement: String?
    }

    init(
        original: String,
        corrected: String,
        modelID: String,
        explanation: String? = nil,
        confidence: Double? = nil,
        customInstruction: String? = nil,
        promptType: String = ""
    ) {
        self.id = UUID()
        self.originalText = original
        self.correctedText = corrected
        self.explanation = explanation
        self.confidence = confidence
        self.diffOperations = CorrectionResult.computeDiff(original: original, corrected: corrected)
        self.timestamp = Date()
        self.modelID = modelID
        self.customInstruction = customInstruction
        self.promptType = promptType
    }

    static func computeDiff(original: String, corrected: String) -> [DiffOp]? {
        guard original != corrected else { return [] }

        let origWords = original.split(separator: " ", omittingEmptySubsequences: false)
        let corrWords = corrected.split(separator: " ", omittingEmptySubsequences: false)

        let diff = corrWords.difference(from: origWords)
        if diff.isEmpty { return [] }

        var ops: [DiffOp] = []
        var offset = 0

        for change in diff {
            switch change {
            case .insert(let wordOffset, let word, _):
                ops.append(DiffOp(type: .insert, offset: wordOffset, length: word.count, replacement: String(word)))
                offset += word.count
            case .remove(let wordOffset, let word, _):
                ops.append(DiffOp(type: .delete, offset: wordOffset, length: word.count, replacement: nil))
            }
        }

        return ops.isEmpty ? nil : ops
    }

    var hasChanges: Bool { originalText != correctedText }
}
