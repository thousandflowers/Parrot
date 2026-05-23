import SwiftUI

struct IgnoreListTab: View {
    @State private var words: [String] = []
    @State private var newWord = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ignored Words")
                .font(.headline)

            Text("Words added here are skipped by the spell checker and ignored during corrections.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Add word…", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addWord() }
                Button("Add") { addWord() }
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.return)
            }

            List {
                if words.isEmpty {
                    Text("No ignored words yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    ForEach(words, id: \.self) { word in
                        HStack {
                            Text(word)
                                .font(.callout)
                            Spacer()
                            Button {
                                removeWord(word)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(word)")
                        }
                    }
                    .onDelete { indexSet in
                        let toRemove = indexSet.map { words[$0] }
                        for word in toRemove { removeWord(word) }
                    }
                }
            }
            .frame(minHeight: 180)
        }
        .padding()
        .onAppear { words = IgnoreList.all() }
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }
        IgnoreList.ignore(trimmed)
        words = IgnoreList.all()
        newWord = ""
    }

    private func removeWord(_ word: String) {
        IgnoreList.remove(word)
        words = IgnoreList.all()
    }
}

#Preview {
    IgnoreListTab()
}
