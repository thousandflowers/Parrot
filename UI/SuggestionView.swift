import SwiftUI

struct SuggestionView: View {
    let result: CorrectionResult?
    let state: SuggestionState
    let onApply: () -> Void
    let onExplain: () -> Void
    let onDismiss: () -> Void

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
        .background(
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
        )
    }

    @ViewBuilder
    private var headerView: some View {
        HStack {
            headerIcon
            Text(headerTitle)
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        case .loading:         return "Analizzando..."
        case .suggestion:      return "Suggerimento"
        case .noErrors:        return "Nessun errore"
        case .error:           return "Errore"
        case .textTooLong:     return "Testo troppo lungo"
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
        case .suggestion(let result):
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
                Text("Il testo e gia corretto!")
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
                    Text("Il testo e troppo lungo (\(length) caratteri)")
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
            case .suggestion:
                Button("Ignora") { onDismiss() }
                Spacer()
                Button("Spiega") { onExplain() }
                Button("Applica") {
                    onApply()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)

            case .error:
                Button("Chiudi") { onDismiss() }
                Spacer()
                Button("Riprova") { onDismiss() }

            case .loading:
                Button("Annulla") { onDismiss() }
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
