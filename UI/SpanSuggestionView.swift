import SwiftUI

/// Displays a list of correction spans with per-fix accept/reject controls.
struct SpanSuggestionView: View {
    let original: String
    @State var spans: [CorrectionSpan]
    let onApply: ([CorrectionSpan]) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if spans.isEmpty {
                emptyState
            } else {
                spanList
            }
            Divider()
            footer
        }
        .frame(width: 420)
        .background(Color.surfaceBackground)
    }

    private var header: some View {
        HStack {
            Text("\(pendingCount) correction\(pendingCount == 1 ? "" : "s")")
                .font(.headline)
            Spacer()
            Button("Accept All") { acceptAll() }
                .buttonStyle(.borderless)
                .foregroundStyle(.green)
            Button("Dismiss") { onDismiss() }
                .buttonStyle(.borderless)
        }
        .padding(12)
    }

    private var spanList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(spans.indices, id: \.self) { i in
                    SpanRowView(
                        span: spans[i],
                        onAccept: { spans[i].accepted = true },
                        onReject: { spans[i].accepted = false }
                    )
                }
            }
            .padding(8)
        }
        .frame(maxHeight: 360)
    }

    private var emptyState: some View {
        Text("No corrections found.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(24)
    }

    private var footer: some View {
        HStack {
            Text("\(acceptedCount) accepted · \(rejectedCount) rejected")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Apply \(acceptedCount > 0 ? "\(acceptedCount) fix\(acceptedCount == 1 ? "" : "es")" : "")") {
                onApply(spans.filter { $0.accepted == true })
            }
            .buttonStyle(.borderedProminent)
            .disabled(acceptedCount == 0)
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private var pendingCount: Int  { spans.filter { $0.accepted == nil }.count }
    private var acceptedCount: Int { spans.filter { $0.accepted == true }.count }
    private var rejectedCount: Int { spans.filter { $0.accepted == false }.count }

    private func acceptAll() {
        for i in spans.indices { spans[i].accepted = true }
    }
}

struct SpanRowView: View {
    let span: CorrectionSpan
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(span.source.displayName)
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(sourceBadgeColor.opacity(0.15))
                .foregroundStyle(sourceBadgeColor)
                .clipShape(RoundedRectangle(cornerRadius: 3))

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(span.original.isEmpty ? "(insert)" : span.original)
                        .strikethrough(!span.original.isEmpty)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(span.replacement)
                        .bold()
                }
                .font(.callout)
                Text(span.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            HStack(spacing: 6) {
                Button { onReject() } label: {
                    Image(systemName: span.accepted == false ? "xmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(span.accepted == false ? .red : .secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Reject suggestion")

                Button { onAccept() } label: {
                    Image(systemName: span.accepted == true ? "checkmark.circle.fill" : "checkmark.circle")
                        .foregroundStyle(span.accepted == true ? .green : .secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Accept suggestion")
            }
        }
        .padding(8)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var rowBackground: Color {
        switch span.accepted {
        case true:  return Color.green.opacity(0.08)
        case false: return Color.red.opacity(0.08)
        case nil:   return Color.surfaceElevated
        }
    }

    private var sourceBadgeColor: Color {
        switch span.source {
        case .nativeGrammar: return .blue
        case .ruleBased:     return .orange
        case .languageTool:  return .purple
        case .llm:           return .mint
        }
    }
}
