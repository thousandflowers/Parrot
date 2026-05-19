import SwiftUI
import AVFoundation

struct SuggestionView: View {
    let result: CorrectionResult?
    let state: SuggestionState
    let onApply: () -> Void
    let onExplain: () -> Void
    let onDismiss: () -> Void
    let onUndo: () -> Void
    let onTranslate: (String) -> Void
    let onCustomAction: (String) -> Void

    @State private var noErrorsShown = false
    @State private var synthesizer = AVSpeechSynthesizer()
    @State private var isSpeaking = false
    @State private var loadingMessageIndex: Int = 0

    private static let loadingMessages = [
        "Analyzing grammar...",
        "Checking verbs...",
        "Verifying punctuation...",
        "Analyzing agreement...",
        "Spell checking..."
    ]

    private var stateHash: Int {
        var hasher = Hasher()
        hasher.combine(headerTitle)
        hasher.combine(result?.detectedTone)
        return hasher.finalize()
    }

    private func speakCorrected(_ text: String) {
        if isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
        isSpeaking = true
        Task {
            while synthesizer.isSpeaking { try? await Task.sleep(for: .milliseconds(100)) }
            isSpeaking = false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            contentView
                .padding(12)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                .id(stateHash)
            Divider()
            footerView
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: 340)
        .animation(.easeOut(duration: 0.18), value: stateHash)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
        .onDisappear {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerView: some View {
        HStack(spacing: 8) {
            headerIcon
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.subheadline.weight(.semibold))
                if let tone = toneLabel {
                    Text(tone)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var toneLabel: String? {
        guard let tone = result?.detectedTone, !tone.isEmpty else { return nil }
        let map = [
            "formal":   String(localized: "suggestion.tone.formal"),
            "informal": String(localized: "suggestion.tone.informal"),
            "neutral":  String(localized: "suggestion.tone.neutral"),
            "academic": String(localized: "suggestion.tone.academic"),
            "technical":String(localized: "suggestion.tone.technical")
        ]
        let prefix = String(localized: "suggestion.tone.detected_prefix")
        return "\(prefix) \(map[tone] ?? tone.capitalized)"
    }

    @ViewBuilder
    private var headerIcon: some View {
        switch state {
        case .loading:
            ProgressView().scaleEffect(0.7)
        case .suggestion:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .fluencySuggestion:
            Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
        case .noErrors:
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.green)
                .scaleEffect(noErrorsShown ? 1.0 : 0.4)
                .onAppear {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { noErrorsShown = true }
                }
                .onDisappear { noErrorsShown = false }
        case .error:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .textTooLong:
            Image(systemName: "text.alignleft").foregroundStyle(.orange)
        case .applied:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .modelMissing:
            Image(systemName: "cpu.fill").foregroundStyle(.orange)
        }
    }

    private var headerTitle: String {
        switch state {
        case .loading:           return String(localized: "panel.analyzing")
        case .suggestion:        return String(localized: "panel.corrected")
        case .fluencySuggestion: return String(localized: "panel.fluency")
        case .noErrors:          return String(localized: "panel.noErrors")
        case .error:             return String(localized: "panel.error")
        case .textTooLong:       return String(localized: "panel.textTooLong")
        case .applied:           return String(localized: "panel.applied")
        case .modelMissing:      return String(localized: "panel.modelMissing")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch state {
        case .loading:
            VStack(spacing: 8) {
                ProgressView()
                Text(Self.loadingMessages[loadingMessageIndex])
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(height: 64)
            .frame(maxWidth: .infinity)
            .onAppear {
                loadingMessageIndex = Int(Date().timeIntervalSince1970) % Self.loadingMessages.count
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(.easeInOut(duration: 0.25)) {
                        loadingMessageIndex = (loadingMessageIndex + 1) % Self.loadingMessages.count
                    }
                }
            }

        case .suggestion(let result, let explanation, let isLoading),
             .fluencySuggestion(let result, let explanation, let isLoading):
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    DiffHighlightView(original: result.originalText, corrected: result.correctedText)
                        .font(.callout)
                    if isLoading {
                        Divider()
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.5).frame(width: 12)
                            Text("Generating explanation...")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else if let explanation {
                        Divider()
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Explanation")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 44, maxHeight: 260)

        case .noErrors:
            Label("Text is already correct", systemImage: "checkmark.shield")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(height: 48)
                .frame(maxWidth: .infinity)

        case .error(let error):
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title3)
                    .foregroundStyle(.red)
                Text(error.errorDescription ?? "Unknown error")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 60)
            .frame(maxWidth: .infinity)

        case .textTooLong(let length, let maxLength):
            VStack(spacing: 4) {
                Text("\(length) characters — limit: \(maxLength)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(height: 48)
            .frame(maxWidth: .infinity)

        case .applied:
            Label("Text replaced", systemImage: "checkmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(height: 48)
                .frame(maxWidth: .infinity)

        case .modelMissing:
            VStack(spacing: 8) {
                Text("No AI model configured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    onDismiss()
                    NSApp.sendAction(Selector(("showSettings:")), to: nil, from: nil)
                }
                .controlSize(.small)
            }
            .frame(minHeight: 60)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerView: some View {
        HStack(spacing: 6) {
            switch state {
            case .suggestion(let r, _, _), .fluencySuggestion(let r, _, _):
                Button(String(localized: "panel.ignore")) { onDismiss() }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    Button { speakCorrected(r.correctedText) }
                        label: { Label(isSpeaking ? "Stop" : "Listen", systemImage: isSpeaking ? "stop.fill" : "speaker.wave.2") }
                    Divider()
                    let detectedLang = LanguageDetector.detect(text: r.originalText, fallbackLanguage: "en")
                    let allLangs: [(String, String)] = [
                        ("en", "English"), ("it", "Italian"), ("es", "Spanish"),
                        ("fr", "French"), ("de", "German"), ("pt", "Portuguese"),
                        ("ru", "Russian"), ("zh", "Chinese"), ("ja", "Japanese"),
                        ("ko", "Korean"), ("ar", "Arabic"), ("nl", "Dutch"), ("tr", "Turkish")
                    ]
                    let filteredLangs = allLangs.filter { code, _ in
                        !detectedLang.hasPrefix(code) && detectedLang != code
                    }
                    Menu("Translate to…") {
                        ForEach(filteredLangs, id: \.0) { code, name in
                            Button(name) { onTranslate(code) }
                        }
                    }
                    Divider()
                    Button("Explain corrections") { onExplain() }
                    Divider()
                    Button("Make formal")    { onCustomAction("Make the text more formal and professional.") }
                    Button("Make informal")  { onCustomAction("Make the text more informal and conversational.") }
                    Button("Shorten")        { onCustomAction("Shorten the text while keeping the main meaning.") }
                    Button("Simplify")       { onCustomAction("Simplify the text to make it clearer and more direct.") }
                    let userPresets = PreferencesStore.shared.presets
                    if !userPresets.isEmpty {
                        Divider()
                        Menu("Presets…") {
                            ForEach(userPresets) { preset in
                                Button(preset.name) { onCustomAction(preset.template) }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)

                Button(String(localized: "panel.apply")) { onApply() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

            case .loading:
                Spacer()
                Button(String(localized: "panel.cancel")) { onDismiss() }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

            case .applied:
                Button(String(localized: "panel.undo")) { onUndo() }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()

            case .error:
                Spacer()
                Button(String(localized: "panel.close")) { onDismiss() }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

            default:
                Spacer()
                Button(String(localized: "panel.close")) { onDismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - VisualEffectView

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
