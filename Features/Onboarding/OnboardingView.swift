import SwiftUI

struct OnboardingView: View {
    @Binding var state: OnboardingState
    @ObservedObject var permissionsViewModel: PermissionsViewModel
    @ObservedObject var speechModelViewModel: SpeechModelViewModel

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.08)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Group {
                    switch state.currentStep {
                    case 0: welcomeStep
                    case 1: permissionsStep
                    default: readyStep
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 16)),
                    removal: .opacity.combined(with: .offset(y: -8))
                ))

                Spacer()

                // Bottom
                HStack {
                    HStack(spacing: 6) {
                        ForEach(0..<OnboardingState.totalSteps, id: \.self) { i in
                            Circle()
                                .fill(i == state.currentStep ? .white.opacity(0.7) : .white.opacity(0.12))
                                .frame(width: 5, height: 5)
                        }
                    }
                    Spacer()
                    if state.currentStep == 1 {
                        Button("Skip") {
                            withAnimation(.easeInOut(duration: 0.25)) { state.isComplete = true }
                        }
                        .buttonStyle(OnboardingGhostButton())
                    }
                    Button(state.currentStep == OnboardingState.totalSteps - 1 ? "Start" : "Continue") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            if state.currentStep >= OnboardingState.totalSteps - 1 {
                                state.isComplete = true
                            } else {
                                state.currentStep += 1
                            }
                        }
                    }
                    .buttonStyle(OnboardingPillButton())
                }
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Text("anna")
                .font(.system(size: 48, weight: .thin))
                .tracking(6)
                .foregroundStyle(.white.opacity(0.88))

            Rectangle().fill(.white.opacity(0.1)).frame(width: 24, height: 1)

            Text("your AI friend, right here on your mac")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(0.5)

            VStack(spacing: 0) {
                hintRow("Right \u{2318}", "Hold to talk")
                hintRow("Right \u{2325}", "Dictation")
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Permissions

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Permissions")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))

            Text("I just need a few things to help you out.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.35))

            VStack(spacing: 1) {
                ForEach(permissionsViewModel.statuses) { s in
                    permRow(s)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Ready

    private var readyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.white.opacity(0.5))

            Text("We're good to go.")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))

            Text("Hold Right \u{2318} anytime — I'm here.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    // MARK: - Rows

    private func hintRow(_ key: String, _ label: String) -> some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .frame(width: 64, alignment: .trailing)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func permRow(_ status: PermissionStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: permIcon(status.kind))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 18)
            Text(status.kind.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            if status.state == .granted {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: "69D3B0"))
            } else {
                Button {
                    permissionsViewModel.request(status.kind)
                } label: {
                    Text("Grant")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
    }

    private func permIcon(_ kind: PermissionKind) -> String {
        switch kind {
        case .microphone: return "mic"
        case .accessibility: return "hand.point.up.left"
        case .automation: return "gearshape.2"
        case .screenRecording: return "rectangle.dashed.badge.record"
        }
    }
}

// MARK: - Button Styles

private struct OnboardingPillButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(.white.opacity(configuration.isPressed ? 0.06 : 0.1), in: Capsule())
    }
}

private struct OnboardingGhostButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.2 : 0.3))
            .padding(.trailing, 8)
    }
}
