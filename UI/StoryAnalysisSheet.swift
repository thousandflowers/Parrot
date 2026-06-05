import SwiftUI

struct StoryAnalysisSheet: View {
    let result: StoryAnalysisResult
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Manuscript Analysis")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Close") {
                    guard let window = NSApp.keyWindow, let sheetParent = window.sheetParent else { return }
                    sheetParent.endSheet(window)
                }
                .keyboardShortcut(.escape)
            }

            HStack(spacing: 16) {
                ScoreCircle(score: result.overallScore)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overall Score")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(result.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .padding()
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(result.categories, id: \.name) { cat in
                        CategoryRow(category: cat)
                    }
                }
                .padding()
            }
        }
        .padding()
        .frame(minWidth: 440, idealWidth: 500, maxWidth: .infinity, minHeight: 380, idealHeight: 420, maxHeight: .infinity)
    }
}

private struct ScoreCircle: View {
    let score: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: score / 10)
                .stroke(scoreColor(score), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(String(format: "%.1f", score))
                .font(.title2.weight(.bold))
        }
        .frame(width: 64, height: 64)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: score)
    }
}

private struct CategoryRow: View {
    let category: StoryAnalysisResult.CategoryScore

    var body: some View {
        HStack(spacing: 12) {
            Text(category.icon)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(category.name)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(String(format: "%.1f/10", category.score))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(scoreColor(category.score))
                }
                Text(category.feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

private func scoreColor(_ score: Double) -> Color {
    if score >= 8 { return .statusOk }
    if score >= 6 { return .statusWarning }
    return .statusError
}

#Preview {
    StoryAnalysisSheet(result: StoryAnalysisResult(
        overallScore: 7.5,
        categories: [
            .init(name: "Plot", score: 8, feedback: "Well-structured narrative arc", icon: "books.vertical.fill"),
            .init(name: "Characters", score: 7, feedback: "Good depth, minor inconsistencies", icon: "person.2.fill"),
            .init(name: "Style", score: 7.5, feedback: "Clean prose with distinctive voice", icon: "pencil.tip"),
        ],
        summary: "A solid manuscript with strong structural foundations. The narrative arc is well-paced and the character development shows promise."
    ))
}
