import SwiftUI

@MainActor
final class OnboardingController {
    static let shared = OnboardingController()

    private var window: NSWindow?

    func showIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") else { return }
        guard window == nil else {
            window?.makeKeyAndOrderFront(nil)
            return
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Benvenuto in RefineClone"
        w.center()
        w.isReleasedWhenClosed = false

        w.contentView = NSHostingView(rootView: OnboardingView(onComplete: { [weak self] in
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            self?.window?.close()
            self?.window = nil
        }))

        window = w
        w.makeKeyAndOrderFront(nil)
    }
}

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            Group {
            switch step {
            case 0: welcomeStep
            case 1: permissionsStep
            default: modelStep
            }
            }
            .animation(.easeInOut(duration: 0.25), value: step)

            Divider()

            HStack {
                if step > 0 {
                    Button("Indietro") { step -= 1 }
                }
                Spacer()
                Text("\(step + 1) / 3")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if step < 2 {
                    Button("Avanti") { step += 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Inizia") { onComplete() }
                        .buttonStyle(.borderedProminent)
                }
                Button("Salta") { onComplete() }
                    .buttonStyle(.borderless)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.shield")
                .font(.system(size: 64))
                .foregroundColor(.statusOk)
            Text("Benvenuto in RefineClone")
                .font(.title)
            Text("Correggi la grammatica ovunque sul tuo Mac.\nNessun dato lascia il computer — tutto funziona offline con un'intelligenza artificiale locale.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var permissionsStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 48))
                .foregroundColor(.statusWarning)
            Text("Permessi di Accessibilità")
                .font(.title2)
            Text("RefineClone ha bisogno dei permessi di Accessibilità per leggere e correggere il testo nelle altre applicazioni.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            Button("Apri Impostazioni di Sistema") {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            }
            Text("Aggiungi RefineClone alla lista delle app autorizzate in Privacy e Sicurezza → Accessibilità.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var modelStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundColor(.accentBrand)
            Text("Scegli un Modello")
                .font(.title2)
            Text("RefineClone usa un modello di linguaggio locale per correggere la grammatica. Puoi scaricare un modello consigliato dalle impostazioni, oppure usare un modello già presente sul tuo computer.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            Text("Vai su Impostazioni → Modelli dopo aver completato il setup.")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}
