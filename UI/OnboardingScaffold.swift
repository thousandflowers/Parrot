import SwiftUI

/// Shared onboarding chrome: a content area above a footer with step dots and
/// Back / Skip / Next (or a final action). Parrot and Wren flows compose this so
/// neither re-implements navigation. `footerAccessory` lets a flow (Wren) show a
/// persistent download bar above the buttons.
struct OnboardingScaffold<Content: View, Accessory: View>: View {
    let step: Int
    let totalSteps: Int
    let finalActionTitle: String
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void
    let onFinish: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footerAccessory: () -> Accessory

    var body: some View {
        VStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.2), value: step)

            Divider()
            footerAccessory()
            footerBar
        }
        .frame(width: 620, height: 520)
        .background(Color.surfaceBackground)
    }

    private var footerBar: some View {
        HStack(spacing: 16) {
            if step > 0 {
                Button("Back", action: onBack)
                    .buttonStyle(.bordered).controlSize(.regular)
            }
            Spacer()
            dots
            Spacer()
            Button("Skip", action: onSkip)
                .buttonStyle(.plain)
                .foregroundStyle(Color.textSecondary)
                .font(.callout)
            if step < totalSteps - 1 {
                Button("Next", action: onNext)
                    .buttonStyle(.borderedProminent).controlSize(.regular)
                    .keyboardShortcut(.return, modifiers: [])
            } else {
                Button(finalActionTitle, action: onFinish)
                    .buttonStyle(.borderedProminent).controlSize(.regular)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Circle()
                    .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: i == step ? 8 : 6, height: i == step ? 8 : 6)
                    .animation(.spring(response: 0.3), value: step)
            }
        }
    }
}

extension OnboardingScaffold where Accessory == EmptyView {
    init(step: Int, totalSteps: Int, finalActionTitle: String,
         onBack: @escaping () -> Void, onNext: @escaping () -> Void,
         onSkip: @escaping () -> Void, onFinish: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(step: step, totalSteps: totalSteps, finalActionTitle: finalActionTitle,
                  onBack: onBack, onNext: onNext, onSkip: onSkip, onFinish: onFinish,
                  content: content, footerAccessory: { EmptyView() })
    }
}
