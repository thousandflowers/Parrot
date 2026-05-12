import SwiftUI

struct SuggestionView: View {
    let result: CorrectionResult?
    let state: SuggestionState
    let onApply: () -> Void
    let onExplain: () -> Void
    let onDismiss: () -> Void
    @State private var feedbackToast = false

    private var stateHash: Int {
        var hasher = Hasher()
        hasher.combine(headerTitle)
        hasher.combine(result?.detectedTone)
        return hasher.finalize()
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()
                .padding(.horizontal, 8)

            contentView
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .id(stateHash)

            Divider()
                .padding(.horizontal, 8)

            footerView
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(minWidth: 300, idealWidth: 380, maxWidth: 500)
        .animation(.easeOut(duration: 0.2), value: stateHash)
        .background(
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
                .cornerRadius(12)
                .shadow(color: .primary.opacity(0.15), radius: 10, x: 0, y: 4)
        )
    }

    @ViewBuilder
    private var headerView: some View {
        HStack {
            headerIcon
            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.headline)
                    .foregroundColor(.primary)
                if let tone = toneLabel {
                    Text(tone)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chiudi")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var toneLabel: String? {
        guard let tone = result?.detectedTone, !tone.isEmpty else { return nil }
        let display: String
        switch tone {
        case "formal": display = "Formale"
        case "informal": display = "Informale"
        case "neutral": display = "Neutrale"
        case "academic": display = "Accademico"
        case "technical": display = "Tecnico"
        default: display = tone.capitalized
        }
        return "Tono rilevato: \(display)"
    }

    @ViewBuilder
    private var headerIcon: some View {
        switch state {
        case .loading:
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
        case .suggestion:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .fluencySuggestion:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.blue)
        case .noErrors:
            Image(systemName: "checkmark.shield.fill")
                .foregroundColor(.green)
        case .error:
            Image(systemName: "xmark.octagon.fill")
                .foregroundColor(.red)
        case .textTooLong:
            Image(systemName: "text.alignleft")
                .foregroundColor(.orange)
        }
    }

    private var headerTitle: String {
        switch state {
        case .loading:         return String(localized: "panel.analyzing")
        case .suggestion:      return String(localized: "panel.corrected")
        case .fluencySuggestion: return String(localized: "panel.fluency")
        case .noErrors:        return String(localized: "panel.noErrors")
        case .error:           return String(localized: "panel.error")
        case .textTooLong:     return String(localized: "panel.error")
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
                    .foregroundColor(.green)
                Text("Il testo è già corretto!")
                    .foregroundColor(.secondary)
            }
            .frame(height: 80)
        case .error(let error):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundColor(.red)
                Text(error.errorDescription ?? "Errore sconosciuto")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(height: 80)
        case .textTooLong(let length, let maxLength):
            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("Il testo è troppo lungo (\(length) caratteri)")
                    Text("Massimo: \(maxLength) caratteri")
                }
                .foregroundColor(.secondary)
            }
            .frame(height: 80)
        }
    }

    @ViewBuilder
    private var footerView: some View {
        HStack {
            switch state {
            case .suggestion, .fluencySuggestion:
                if feedbackToast {
                    Text("Segnalato, grazie")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                } else {
                    Button(String(localized: "panel.ignore")) { onDismiss() }
                        .accessibilityHint("Scarta il suggerimento senza applicarlo")
                    Button(String(localized: "panel.reportError")) {
                        if let r = result {
                            FeedbackLogger.log(original: r.originalText, corrected: r.correctedText, modelID: r.modelID)
                        }
                        feedbackToast = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            feedbackToast = false
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                Spacer()
                Button(String(localized: "panel.explain")) { onExplain() }
                    .accessibilityHint("Richiedi una spiegazione delle correzioni")
                Button(String(localized: "panel.apply")) {
                    onApply()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Sostituisci il testo con la versione corretta")

            case .error:
                Button(String(localized: "panel.close")) { onDismiss() }
                    .accessibilityHint("Chiudi il messaggio di errore")
                Spacer()

            case .loading:
                Button("Annulla controllo") { onDismiss() }
                    .accessibilityHint("Annulla l'elaborazione in corso")
                Spacer()

            default:
                Button("Chiudi") { onDismiss() }
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("Chiudi il pannello")
                Spacer()
            }
        }
        .animation(.easeOut(duration: 0.25), value: feedbackToast)
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
