import SwiftUI
import AVFoundation

@MainActor
private final class SpeechController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    @Published var isSpeaking = false
    private var continuationTask: Task<Void, Never>?

    func speak(_ text: String) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.delegate = self
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        continuationTask?.cancel()
        continuationTask = nil
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

struct SuggestionView: View {
    let result: CorrectionResult?
    let state: SuggestionState
    let onApply: () -> Void
    let onExplain: () -> Void
    let onDismiss: () -> Void
    let onUndo: () -> Void
    let onTranslate: (String) -> Void
    let onCustomAction: (String) -> Void
    let onIgnoreWord: (String) -> Void
    let onRunFlow: (Flow) -> Void

    @StateObject private var speech = SpeechController()
    @State private var noErrorsShown = false
    @State private var loadingMessageIndex: Int = 0
    @State private var showSideBySideDiff = false
    @State private var appeared = false
    @State private var closeHovered = false
    @State private var appliedProgress: Double = 1.0

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
        if speech.isSpeaking {
            speech.stop()
            return
        }
        speech.speak(text)
    }

    private func firstChangedWord(in result: CorrectionResult) -> String? {
        // Skip word-diff for CJK text (no whitespace word boundaries)
        if result.correctedText.unicodeScalars.contains(where: {
            ($0.value >= 0x4E00 && $0.value <= 0x9FFF) ||
            ($0.value >= 0x3040 && $0.value <= 0x30FF) ||
            ($0.value >= 0xAC00 && $0.value <= 0xD7AF)
        }) { return nil }
        let origWords = result.originalText.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        let corrWords = result.correctedText.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        for (i, cw) in corrWords.enumerated() {
            guard cw.count > 2 else { continue }
            if i >= origWords.count || cw != origWords[i] { return cw }
        }
        return nil
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
        .frame(width: 340, height: 280)
        .animation(.easeOut(duration: 0.18), value: stateHash)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 6)
        .scaleEffect(appeared ? 1.0 : 0.93)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { appeared = true }
        }
        .onDisappear {
            speech.stop()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerView: some View {
        HStack(spacing: 8) {
            headerIcon
                .frame(width: 16, height: 16)
            Text(headerTitle)
                .font(.subheadline.weight(.semibold))
            if let tone = toneLabel {
                Text("·")
                    .foregroundStyle(.quaternary)
                Text(tone)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(closeHovered ? Color.primary.opacity(0.65) : .secondary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.primary.opacity(closeHovered ? 0.12 : 0.06)))
                    .scaleEffect(closeHovered ? 1.12 : 1.0)
                    .animation(.easeOut(duration: 0.12), value: closeHovered)
            }
            .buttonStyle(.plain)
            .onHover { closeHovered = $0 }
            .accessibilityLabel("Close")
            .frame(minWidth: 44, minHeight: 44)
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
        case .streaming:
            Image(systemName: "waveform").foregroundStyle(Color.accentColor)
        case .suggestion:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.statusOk)
        case .fluencySuggestion:
            Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
        case .noErrors:
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(Color.statusOk)
                .scaleEffect(noErrorsShown ? 1.0 : 0.4)
                .onAppear {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { noErrorsShown = true }
                }
                .onDisappear { noErrorsShown = false }
        case .error:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(Color.statusError)
        case .textTooLong:
            Image(systemName: "text.alignleft").foregroundStyle(Color.statusWarning)
        case .applied:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.statusOk)
        case .modelMissing:
            Image(systemName: "cpu.fill").foregroundStyle(Color.statusWarning)
        }
    }

    private var headerTitle: String {
        switch state {
        case .loading:           return String(localized: "panel.analyzing")
        case .streaming:         return String(localized: "panel.streaming")
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

        case .streaming(let original, let current):
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if current.isEmpty {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text("Generating correction…")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            DiffHighlightView(original: original, corrected: current)
                                .font(.callout)
                        }
                        Color.clear.frame(height: 1).id("streamEnd")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 44, maxHeight: 260)
                .onChange(of: current) { _, _ in
                    proxy.scrollTo("streamEnd", anchor: .bottom)
                }
            }

        case .suggestion(let result, let explanation, let isLoading),
             .fluencySuggestion(let result, let explanation, let isLoading):
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if showSideBySideDiff {
                        SideBySideDiffView(original: result.originalText, corrected: result.correctedText)
                            .font(.callout)
                    } else {
                        DiffHighlightView(original: result.originalText, corrected: result.correctedText)
                            .font(.callout)
                    }
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
                    .foregroundStyle(Color.statusError)
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
            VStack(spacing: 10) {
                Label("Text replaced", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.1)).frame(height: 2)
                        Capsule()
                            .fill(Color.statusOk.opacity(0.7))
                            .frame(width: geo.size.width * appliedProgress, height: 2)
                    }
                }
                .frame(height: 2)
            }
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .onAppear {
                appliedProgress = 1.0
                withAnimation(.linear(duration: 4.8)) { appliedProgress = 0.0 }
            }

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
                Button(String(localized: "panel.ignore")) {
                    if let firstChanged = firstChangedWord(in: r) {
                        onIgnoreWord(firstChanged)
                    }
                    onDismiss()
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showSideBySideDiff.toggle()
                } label: {
                    Image(systemName: showSideBySideDiff ? "rectangle.split.3x1.fill" : "rectangle.split.2x1")
                        .font(.system(size: 14))
                        .foregroundStyle(showSideBySideDiff ? Color.accentBrand : .secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .help(showSideBySideDiff ? "Showing side-by-side — click for inline diff" : "Showing inline diff — click for side-by-side")
                .accessibilityLabel(showSideBySideDiff ? "Side-by-side view" : "Inline diff view")

                Menu {
                    menuListenAction(r)
                    Divider()
                    menuTranslateTo(r)
                    Divider()
                    menuExplainAction
                    Divider()
                    menuRewriteActions
                    let userPresets = PreferencesStore.shared.presets
                    if !userPresets.isEmpty {
                        Divider()
                        menuPresets(userPresets)
                    }
                    let userFlows = PreferencesStore.shared.flows
                    if !userFlows.isEmpty {
                        Divider()
                        menuFlows(userFlows)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel("More options")

                Button(String(localized: "panel.apply")) { onApply() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

            case .loading, .streaming:
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

    // MARK: - Footer menu sections

    @ViewBuilder
    private func menuListenAction(_ r: CorrectionResult) -> some View {
        Button { speakCorrected(r.correctedText) }
            label: { Label(speech.isSpeaking ? "Stop" : "Listen", systemImage: speech.isSpeaking ? "stop.fill" : "speaker.wave.2") }
    }

    @ViewBuilder
    private func menuTranslateTo(_ r: CorrectionResult) -> some View {
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
    }

    private var menuExplainAction: some View {
        Button("Explain corrections") { onExplain() }
    }

    @ViewBuilder
    private var menuRewriteActions: some View {
        Button("Make formal")    { onCustomAction("Make the text more formal and professional.") }
        Button("Make informal")  { onCustomAction("Make the text more informal and conversational.") }
        Button("Shorten")        { onCustomAction("Shorten the text while keeping the main meaning.") }
        Button("Simplify")       { onCustomAction("Simplify the text to make it clearer and more direct.") }
    }

    @ViewBuilder
    private func menuPresets(_ presets: [Preset]) -> some View {
        Menu("Presets…") {
            ForEach(presets) { preset in
                Button(preset.name) { onCustomAction(preset.template) }
            }
        }
    }

    @ViewBuilder
    private func menuFlows(_ flows: [Flow]) -> some View {
        Menu("Flows…") {
            ForEach(flows) { flow in
                Button(flow.name) { onRunFlow(flow) }
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
