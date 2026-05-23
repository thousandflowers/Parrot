import SwiftUI

struct PlagiarismTab: View {
    @State private var selectedMethods: Set<String> = Set(PlagiarismMethod.allCases.map { $0.rawValue })
    @State private var inputText = ""
    @State private var result: PlagiarismResult?
    @State private var isChecking = false
    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                TextEditor(text: $inputText)
                    .frame(minHeight: 80)
                    .border(.separator, width: 0.5)
                    .accessibilityLabel("Text to check")
            } header: {
                Text("Text to check")
            }

            Section {
                ForEach(PlagiarismMethod.allCases) { method in
                    Toggle(isOn: Binding(
                        get: { selectedMethods.contains(method.rawValue) },
                        set: { isSelected in
                            if isSelected { selectedMethods.insert(method.rawValue) }
                            else { selectedMethods.remove(method.rawValue) }
                        }
                    )) {
                        Label(method.rawValue, systemImage: method.icon)
                    }
                }
            } header: {
                Text("Detection methods")
            }

            Section {
                if isChecking {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking…")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                } else {
                    Button(action: checkPlagiarism) {
                        Label("Check", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(inputText.isEmpty || selectedMethods.isEmpty)
                    .accessibilityHint("Checks the selected text for plagiarism using the chosen detection methods")
                }

                if let result {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Overall match: \(Int(result.overallScore * 100))%")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Circle()
                                .fill(result.overallScore > 0.5 ? Color.statusError : result.overallScore > 0.3 ? Color.statusWarning : Color.statusOk)
                                .frame(width: 10, height: 10)
                        }

                        ForEach(result.findings, id: \.matchText) { finding in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(finding.source.rawValue)
                                        .font(.caption.weight(.semibold))
                                    Spacer()
                                    Text("\(Int(finding.confidence * 100))%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(finding.matchText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                if let url = finding.url {
                                    Link("Search", destination: URL(string: url)!)
                                        .font(.caption2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(.easeOut(duration: 0.3), value: result.overallScore)
                }
            } header: {
                Text("Results")
            }
        }
        .formStyle(.grouped)
        .onDisappear { checkTask?.cancel() }
    }

    private func checkPlagiarism() {
        isChecking = true
        checkTask?.cancel()
        checkTask = Task {
            let methods = Set(selectedMethods.compactMap { PlagiarismMethod(rawValue: $0) })
            let detected = await PlagiarismDetector.shared.detect(text: inputText, methods: methods)
            guard !Task.isCancelled else { return }
            result = detected
            isChecking = false
        }
    }
}

#Preview {
    PlagiarismTab()
}
