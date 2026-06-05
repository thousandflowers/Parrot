import SwiftUI

/// Wren's first-run flow. Replaced with the full multi-step flow in later tasks.
struct WrenOnboardingView: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome to Wren").font(.largeTitle.bold())
            Button("Start using Wren") { onComplete() }
                .buttonStyle(.borderedProminent)
        }
        .frame(width: 620, height: 520)
        .background(Color.surfaceBackground)
    }
}
