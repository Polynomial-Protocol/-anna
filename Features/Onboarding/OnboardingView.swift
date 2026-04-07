import SwiftUI

struct OnboardingView: View {
    @Binding var state: OnboardingState
    @ObservedObject var permissionsViewModel: PermissionsViewModel
    @ObservedObject var speechModelViewModel: SpeechModelViewModel

    var body: some View {
        ZStack {
            AnnaPalette.canvas.ignoresSafeArea()

            HStack(spacing: 0) {
                leftColumn
                rightColumn
            }
            .padding(30)
        }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Anna")
                .font(.system(size: 72, weight: .black))
                .foregroundStyle(.white.opacity(0.92))

            Text("A smart assistant for your Mac that listens on demand, teaches you how things work, guides you visually, and stays visible only through your menu bar.")
                .font(.title2.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: 560, alignment: .leading)

            // Progress dots
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { step in
                    Capsule()
                        .fill(step <= state.currentStep ? AnnaPalette.accent : Color.white.opacity(0.12))
                        .frame(width: step == state.currentStep ? 28 : 8, height: 8)
                        .animation(.spring(response: 0.35), value: state.currentStep)
                }
            }
            .padding(.vertical, 4)

            // Steps
            VStack(alignment: .leading, spacing: 16) {
                onboardingStep(
                    index: 1,
                    title: "Hold to talk",
                    body: "Hold Right ⌘ to give Anna a task. Hold Right ⌥ to dictate into the focused field."
                )
                onboardingStep(
                    index: 2,
                    title: "Visual guidance",
                    body: "Anna points at UI elements on your screen with a blue cursor to show you exactly where to click."
                )
                onboardingStep(
                    index: 3,
                    title: "Grant permissions",
                    body: "Microphone, Accessibility, Screen Recording, and Automation — each unlocks a capability."
                )
                onboardingStep(
                    index: 4,
                    title: "Voice responses",
                    body: "Anna speaks her responses aloud so you can keep your eyes on what you're doing."
                )
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AnnaPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )

            HStack(spacing: 14) {
                Button("Continue to Permission Setup") {
                    withAnimation(.spring(response: 0.35)) {
                        state.currentStep = 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AnnaPalette.accent)

                Button("Skip for now") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        state.isComplete = true
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 28)
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(state.currentStep == 0 ? "First-run brief" : "Permission center")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white.opacity(0.92))

            if state.currentStep == 0 {
                Text("Anna starts with a calm introduction instead of asking for every permission at once.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                StatusPill(text: "Direct distribution", color: AnnaPalette.warning)
                StatusPill(text: "Voice + Visual guidance", color: AnnaPalette.copper)
                StatusPill(text: "Confirmation before purchases", color: AnnaPalette.mint)
                modelDownloadCard
            } else {
                PermissionCenterView(viewModel: permissionsViewModel)
                modelDownloadCard
                HStack {
                    Spacer()
                    Button("Finish setup") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            state.isComplete = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AnnaPalette.accent)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AnnaPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .frame(width: 440)
    }

    private var modelDownloadCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Speech model")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white.opacity(0.92))
            Text("Parakeet v2 English via FluidAudio. Best recall for fast command routing on Apple Silicon.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
            StatusPill(
                text: speechModelViewModel.status.state.rawValue.capitalized,
                color: color(for: speechModelViewModel.status.state)
            )
            Text(speechModelViewModel.status.detail)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            HStack {
                Button("Download Parakeet") {
                    speechModelViewModel.download()
                }
                .buttonStyle(.borderedProminent)
                .tint(AnnaPalette.accent)

                Button("Refresh") {
                    Task { await speechModelViewModel.refresh() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private func onboardingStep(index: Int, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(index)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(AnnaPalette.accent, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func color(for state: SpeechModelState) -> Color {
        switch state {
        case .ready: return AnnaPalette.mint
        case .downloading: return AnnaPalette.copper
        case .failed: return .red
        case .notInstalled: return AnnaPalette.warning
        }
    }
}
