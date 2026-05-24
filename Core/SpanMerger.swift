import Foundation

enum SpanMerger {
    static func merge(_ spans: [CorrectionSpan]) -> [CorrectionSpan] {
        guard !spans.isEmpty else { return [] }
        let sorted = spans.sorted {
            if $0.range.location != $1.range.location { return $0.range.location < $1.range.location }
            return $0.source > $1.source
        }
        var result: [CorrectionSpan] = []
        var lastEnd = -1
        for span in sorted {
            let spanEnd = span.range.location + span.range.length
            if span.range.location >= lastEnd {
                result.append(span)
                lastEnd = spanEnd
            } else {
                guard let last = result.last else { continue }
                if span.source > last.source ||
                   (span.source == last.source && span.confidence > last.confidence) {
                    result[result.count - 1] = span
                    lastEnd = spanEnd
                }
            }
        }
        return result
    }
}
