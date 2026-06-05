import SwiftUI
import UniformTypeIdentifiers

/// Reusable tone-capture UI: finish curated phrases (default) + optional paste + optional upload.
/// Used by Wren onboarding step 2 and by the recurring tune-up. Calls `ToneSeeder`; reports the
/// learned count via `onLearned`. Fully optional — the host provides Skip/Next.
struct TonePracticeView: View {
    let phrases: [TonePhrases.Phrase]
    var onLearned: (Int) -> Void = { _ in }

    @State private var continuations: [String]
    @State private var showPaste = false
    @State private var pasted = ""
    @State private var learnedCount: Int?
    @State private var isWorking = false

    init(phrases: [TonePhrases.Phrase], onLearned: @escaping (Int) -> Void = { _ in }) {
        self.phrases = phrases
        self.onLearned = onLearned
        _continuations = State(initialValue: Array(repeating: "", count: phrases.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Teach Wren your tone")
                .font(.title2.bold())
            Text("Finish a few sentences the way you'd actually write them. Optional — skip anytime.")
                .font(.callout).foregroundStyle(Color.textSecondary)

            ForEach(Array(phrases.enumerated()), id: \.offset) { idx, phrase in
                VStack(alignment: .leading, spacing: 4) {
                    Text(phrase.opener).font(.callout.weight(.medium))
                    TextField("…continue in your words", text: $continuations[idx], axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                }
            }

            DisclosureGroup("Or paste your own text", isExpanded: $showPaste) {
                TextEditor(text: $pasted)
                    .font(.body).frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.borderDefault.opacity(0.5)))
            }
            .font(.callout)

            HStack(spacing: 12) {
                Button("Upload a document…", action: pickFiles)
                    .buttonStyle(.bordered).controlSize(.small)
                Button(isWorking ? "Learning…" : "Learn my tone", action: learn)
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(isWorking)
                if let n = learnedCount {
                    Text(n > 0 ? "Learned \(n) patterns from your style"
                               : "I'll use this as a hint")
                        .font(.caption).foregroundStyle(Color.statusOk)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func learn() {
        isWorking = true
        let pairs = zip(phrases, continuations).map { (opener: $0.0.opener, continuation: $0.1) }
        let pasteText = showPaste ? pasted : nil
        Task {
            let r = await ToneSeeder.learn(phraseCompletions: pairs, pastedText: pasteText)
            await MainActor.run {
                learnedCount = r.seededCount
                isWorking = false
                onLearned(r.seededCount)
            }
        }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        isWorking = true
        Task {
            let r = await ToneSeeder.learn(fromFiles: urls)
            await MainActor.run {
                learnedCount = r.seededCount
                isWorking = false
                onLearned(r.seededCount)
            }
        }
    }
}
