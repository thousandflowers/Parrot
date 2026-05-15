import SwiftUI

struct SuggestionView: View {
    let result: CorrectionResult?
    let state: SuggestionState
    let onApply: () -> Void
    let onExplain: () -> Void
    let onDismiss: () -> Void
    let onUndo: () -> Void
    @State private var noErrorsShown = false

    private static let loadingMessages = [
        "Analizzando la grammatica...",
        "Controllando i verbi...",
        "Verificando la punteggiatura...",
        "Analisi delle concordanze...",
        "Controllo ortografico in corso..."
    ]
    @State private var loadingMessageIndex: Int = 0

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
                    .foregroundColor(.textPrimary)
                if let tone = toneLabel {
                    Text(tone)
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                }
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.textSecondary)
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
                .foregroundColor(.statusOk)
            case .fluencySuggestion:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.accentBrand)
            case .noErrors:
            Image(systemName: "checkmark.shield.fill")
                .foregroundColor(.statusOk)
                .scaleEffect(noErrorsShown ? 1.0 : 0.3)
                .onAppear {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        noErrorsShown = true
                    }
                }
                .onDisappear { noErrorsShown = false }
        case .error:
            Image(systemName: "xmark.octagon.fill")
                .foregroundColor(.statusError)
        case .textTooLong:
            Image(systemName: "text.alignleft")
                .foregroundColor(.statusWarning)
        case .applied:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.statusOk)
        case .modelMissing:
            Image(systemName: "cpu.fill")
                .foregroundColor(.statusWarning)
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
        case .applied:         return "Testo applicato"
        case .modelMissing:    return "Modello non trovato"
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch state {
        case .loading:
            VStack {
                ProgressView(Self.loadingMessages[loadingMessageIndex])
                    .frame(height: 60)
            }
            .onAppear {
                loadingMessageIndex = Int(Date().timeIntervalSince1970) % Self.loadingMessages.count
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(.easeInOut(duration: 0.3)) {
                        loadingMessageIndex = (loadingMessageIndex + 1) % Self.loadingMessages.count
                    }
                }
            }
        case .suggestion(let result, let explanation, let isLoading):
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(result.correctedText)
                        .font(.body)
                        .textSelection(.enabled)
                    
                    if isLoading {
                        Divider()
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.5)
                            Text("Generazione spiegazione...")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                    } else if let explanation = explanation {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Spiegazione")
                                .font(.caption.bold())
                                .foregroundColor(.accentBrand)
                            Text(explanation)
                                .font(.subheadline)
                                .foregroundColor(.textSecondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 60, maxHeight: 300)
        case .fluencySuggestion(let result, let explanation, let isLoading):
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(result.correctedText)
                        .font(.body)
                        .textSelection(.enabled)
                    
                    if isLoading {
                        Divider()
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.5)
                            Text("Generazione spiegazione...")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                    } else if let explanation = explanation {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Miglioramento fluidità")
                                .font(.caption.bold())
                                .foregroundColor(.accentBrand)
                            Text(explanation)
                                .font(.subheadline)
                                .foregroundColor(.textSecondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 60, maxHeight: 300)
        case .noErrors:
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.largeTitle)
                .foregroundColor(.statusOk)
                Text("Il testo è già corretto!")
                    .foregroundColor(.textSecondary)
            }
            .frame(height: 80)
        case .error(let error):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                .foregroundColor(.statusError)
                Text(error.errorDescription ?? "Errore sconosciuto")
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(height: 80)
        case .textTooLong(let length, let maxLength):
            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("Il testo è troppo lungo (\(length) caratteri)")
                    Text("Massimo: \(maxLength) caratteri")
                }
                .foregroundColor(.textSecondary)
            }
            .frame(height: 80)
        case .applied:
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.largeTitle)
                    .foregroundColor(.statusOk)
                Text("Il testo è stato sostituito correttamente.")
                    .foregroundColor(.textSecondary)
                    .font(.subheadline)
            }
            .frame(height: 80)
        case .modelMissing:
            VStack(spacing: 12) {
                Text("Nessun modello AI è installato.")
                    .foregroundColor(.textSecondary)
                Button("Vai ai Modelli") {
                    onDismiss()
                    NSApp.sendAction(Selector(("showSettings:")), to: nil, from: nil)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(height: 80)
        }
    }

    @ViewBuilder
    private var footerView: some View {
        HStack {
            switch state {
            case .suggestion, .fluencySuggestion:
                Button(String(localized: "panel.ignore")) { onDismiss() }
                    .accessibilityHint("Scarta il suggerimento senza applicarlo")
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

            case .applied:
                Spacer()
                Button("Annulla") { onUndo() }
                    .accessibilityHint("Ripristina il testo originale")
                Spacer()

            case .modelMissing:
                Button("Chiudi") { onDismiss() }
                Spacer()

            default:
                Button("Chiudi") { onDismiss() }
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("Chiudi il pannello")
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
