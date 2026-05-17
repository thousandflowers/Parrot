import SwiftUI

struct SuggestionView: View {
    let result: CorrectionResult?
    let state: SuggestionState
    let onApply: () -> Void
    let onExplain: () -> Void
    let onDismiss: () -> Void
    let onRetry: () -> Void
    let onUpgradeToAI: (() -> Void)?

    init(
        result: CorrectionResult?,
        state: SuggestionState,
        onApply: @escaping () -> Void,
        onExplain: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onRetry: @escaping () -> Void,
        onUpgradeToAI: (() -> Void)? = nil
    ) {
        self.result = result
        self.state = state
        self.onApply = onApply
        self.onExplain = onExplain
        self.onDismiss = onDismiss
        self.onRetry = onRetry
        self.onUpgradeToAI = onUpgradeToAI
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()
                .padding(.horizontal, 8)

            contentView
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()
                .padding(.horizontal, 8)

            footerView
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: 380)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator.opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var headerView: some View {
        HStack {
            headerIcon
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(headerTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let source = result?.source {
                        sourceBadge(for: source)
                    }
                }
                if let tone = toneLabel {
                    Text(tone)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Chiudi")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func sourceBadge(for source: CorrectionResult.CorrectionSource) -> some View {
        switch source {
        case .ruleBased:
            Text("⚡")
                .font(.caption2)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.orange.opacity(0.15), in: .capsule)
        case .llm:
            Text("🤖")
                .font(.caption2)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.blue.opacity(0.15), in: .capsule)
        case .hybrid:
            Text("⚡+AI")
                .font(.caption2)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.purple.opacity(0.15), in: .capsule)
        }
    }

    private var toneLabel: String? {
        guard let tone = result?.detectedTone, !tone.isEmpty else { return nil }
        let display: String
        switch tone {
        case "formal":   display = String(localized: "suggestion.tone.formal")
        case "informal": display = String(localized: "suggestion.tone.informal")
        case "neutral":  display = String(localized: "suggestion.tone.neutral")
        case "academic": display = String(localized: "suggestion.tone.academic")
        case "technical":display = String(localized: "suggestion.tone.technical")
        default:         display = tone.capitalized
        }
        return "\(String(localized: "suggestion.tone.detected_prefix")) \(display)"
    }

    @ViewBuilder
    private var headerIcon: some View {
        switch state {
        case .loading:
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
                .accessibilityLabel("Analisi in corso")
        case .streaming:
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
                .accessibilityLabel("Correzione in corso")
        case .suggestion:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.refineSuccess)
                .accessibilityLabel("Suggerimento disponibile")
        case .fluencySuggestion:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.refineFluency)
                .accessibilityLabel("Suggerimento fluidità")
        case .noErrors:
            Image(systemName: "checkmark.shield.fill")
                .foregroundColor(.refineSuccess)
                .accessibilityLabel("Nessun errore")
        case .error:
            Image(systemName: "xmark.octagon.fill")
                .foregroundColor(.refineError)
                .accessibilityLabel("Errore")
        case .textTooLong:
            Image(systemName: "text.alignleft")
                .foregroundColor(.refineWarning)
                .accessibilityLabel("Testo troppo lungo")
        }
    }

    private var headerTitle: String {
        switch state {
        case .loading:           return String(localized: "suggestion.header.analyzing")
        case .streaming:         return String(localized: "suggestion.header.correcting")
        case .suggestion:        return String(localized: "suggestion.header.suggestion")
        case .fluencySuggestion: return String(localized: "suggestion.header.fluency")
        case .noErrors:          return String(localized: "suggestion.header.no_errors")
        case .error:             return String(localized: "suggestion.header.error")
        case .textTooLong:       return String(localized: "suggestion.header.too_long")
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch state {
        case .loading:
            VStack {
                ProgressView("Elaborazione in corso...")
                    .frame(height: 60)
            }
        case .streaming(let original, let accumulated):
            ScrollView(.vertical) {
                DiffHighlightView(original: original, corrected: accumulated)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 60, maxHeight: 300)
        case .suggestion(let result), .fluencySuggestion(let result):
            ScrollView(.vertical) {
                Text(result.correctedText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 60, maxHeight: 200)
        case .noErrors:
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.largeTitle)
                    .foregroundColor(.refineSuccess)
                    .accessibilityHidden(true)
                Text("Il testo è già corretto!")
                    .foregroundStyle(.secondary)
            }
            .frame(height: 80)
        case .error(let error):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundColor(.refineError)
                    .accessibilityHidden(true)
                Text(error.errorDescription ?? "Errore sconosciuto")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(height: 80)
        case .textTooLong(let length, let maxLength):
            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("Il testo è troppo lungo (\(length) caratteri)")
                    Text("Massimo: \(maxLength) caratteri")
                }
                .foregroundStyle(.secondary)
            }
            .frame(height: 80)
        }
    }

    @ViewBuilder
    private var footerView: some View {
        HStack {
            switch state {
            case .suggestion, .fluencySuggestion:
                Button("Ignora") { onDismiss() }
                Spacer()
                if result?.source == .ruleBased, onUpgradeToAI != nil {
                    Button("Migliora con AI") { onUpgradeToAI?() }
                        .buttonStyle(.bordered)
                }
                Button("Spiega") { onExplain() }
                Button("Applica") {
                    onApply()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)

            case .error:
                Button("Chiudi") { onDismiss() }
                Spacer()
                Button("Riprova") { onRetry() }

            case .loading:
                Button("Annulla") { onDismiss() }
                Spacer()

            case .streaming:
                Button("Annulla") { onDismiss() }
                    .accessibilityHint("Annulla la correzione in streaming")
                Spacer()

            default:
                Button("Chiudi") { onDismiss() }
                .keyboardShortcut(.defaultAction)
                Spacer()
            }
        }
    }
}

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
