import SwiftUI

struct SideBySideDiffView: View {
    let original: String
    let corrected: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            diffPane(text: original, diff: WordDiff(original: original, corrected: corrected), role: .original)
            Divider()
            diffPane(text: corrected, diff: WordDiff(original: original, corrected: corrected), role: .corrected)
        }
    }

    private func diffPane(text: String, diff: WordDiff, role: DiffRole) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(role.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(attributedDiffText(diff: diff, role: role))
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func attributedDiffText(diff: WordDiff, role: DiffRole) -> AttributedString {
        var result = AttributedString()

        for segment in diff.segments {
            switch segment {
            case .same(let word):
                let attrs = AttributedString(word)
                result.append(attrs)
                result.append(AttributedString(" "))
            case .added(let word):
                if role == .corrected {
                    var attrs = AttributedString(word)
                    attrs.backgroundColor = Color.statusOk.opacity(0.2)
                    result.append(attrs)
                }
                result.append(AttributedString(" "))
            case .removed(let word):
                if role == .original {
                    var attrs = AttributedString(word)
                    attrs.backgroundColor = Color.statusError.opacity(0.15)
                    attrs.strikethroughStyle = .single
                    attrs.strikethroughColor = NSColor.statusError
                    result.append(attrs)
                }
                result.append(AttributedString(" "))
            }
        }

        return result
    }

    enum DiffRole { case original, corrected
        var label: String {
            switch self {
            case .original: return "Original"
            case .corrected: return "Corrected"
            }
        }
    }
}

// MARK: - Word-level diff engine

private struct WordDiff {
    let segments: [Segment]

    enum Segment: Equatable {
        case same(String)
        case added(String)
        case removed(String)
    }

    init(original: String, corrected: String) {
        let ow = original.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let cw = corrected.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let lcs = Self.lcs(ow, cw)
        var segments: [Segment] = []
        var o = 0, c = 0

        for common in lcs {
            while o < ow.count, ow[o] != common {
                segments.append(.removed(ow[o])); o += 1
            }
            while c < cw.count, cw[c] != common {
                segments.append(.added(cw[c])); c += 1
            }
            if o < ow.count { segments.append(.same(ow[o])); o += 1; c += 1 }
        }
        while o < ow.count { segments.append(.removed(ow[o])); o += 1 }
        while c < cw.count { segments.append(.added(cw[c])); c += 1 }

        self.segments = segments
    }

    /// Longest Common Subsequence (Hunt–Szymanski style)
    private static func lcs(_ a: [String], _ b: [String]) -> [String] {
        let m = a.count, n = b.count
        guard m > 0, n > 0 else { return [] }
        var prev = [Int](repeating: 0, count: n + 1)
        var cur  = [Int](repeating: 0, count: n + 1)
        for i in 1...m {
            for j in 1...n {
                cur[j] = a[i-1] == b[j-1] ? prev[j-1] + 1 : max(prev[j], cur[j-1])
            }
            (prev, cur) = (cur, prev)
        }
        var res: [String] = []
        var i = m, j = n
        while i > 0, j > 0 {
            if a[i-1] == b[j-1] { res.append(a[i-1]); i -= 1; j -= 1 }
            else if prev[j] >= cur[j-1] { i -= 1 }
            else { j -= 1 }
        }
        return res.reversed()
    }
}
