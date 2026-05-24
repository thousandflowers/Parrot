import Foundation

struct CorrectionSpan: Sendable, Identifiable {
    let id: UUID
    let range: NSRange
    let original: String
    let replacement: String
    let reason: String
    let confidence: Double
    let source: SpanSource
    var accepted: Bool?

    init(range: NSRange, original: String, replacement: String,
         reason: String, confidence: Double, source: SpanSource) {
        self.id = UUID()
        self.range = range
        self.original = original
        self.replacement = replacement
        self.reason = reason
        self.confidence = confidence
        self.source = source
        self.accepted = nil
    }
}

enum SpanSource: Int, Comparable, Sendable {
    case nativeGrammar = 0
    case ruleBased     = 1
    case languageTool  = 2
    case llm           = 3

    static func < (lhs: SpanSource, rhs: SpanSource) -> Bool { lhs.rawValue < rhs.rawValue }

    var displayName: String {
        switch self {
        case .nativeGrammar: return "macOS"
        case .ruleBased:     return "Rules"
        case .languageTool:  return "LanguageTool"
        case .llm:           return "AI"
        }
    }
}

enum SpanApplicator {
    static func apply(spans: [CorrectionSpan], to text: String) -> String {
        let sorted = deoverlap(spans.sorted { $0.range.location > $1.range.location })
        var result = text
        for span in sorted {
            guard let swiftRange = Range(span.range, in: result) else { continue }
            result.replaceSubrange(swiftRange, with: span.replacement)
        }
        return result
    }

    static func deoverlap(_ sortedDescending: [CorrectionSpan]) -> [CorrectionSpan] {
        var kept: [CorrectionSpan] = []
        for span in sortedDescending {
            let overlaps = kept.contains { existing in
                let a = span.range
                let b = existing.range
                return a.location < b.location + b.length && b.location < a.location + a.length
            }
            if !overlaps { kept.append(span) }
        }
        return kept
    }
}
