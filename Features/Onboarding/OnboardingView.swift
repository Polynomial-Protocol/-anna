import SwiftUI

struct OnboardingView: View {
    @Binding var state: OnboardingState
    @ObservedObject var permissionsViewModel: PermissionsViewModel
    @ObservedObject var speechModelViewModel: SpeechModelViewModel

    @State private var appeared = false
    @State private var permissionIndex = 0

    private let permissions = PermissionKind.onboardingSequence

    private var currentPermission: PermissionKind? {
        guard state.currentStep == 2, permissionIndex < permissions.count else { return nil }
        return permissions[permissionIndex]
    }

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.08)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Group {
                    switch state.currentStep {
                    case 0: welcomeStep
                    case 1: capabilitiesStep
                    case 2: permissionRequestStep
                    case 3: completionStep
                    default: completionStep
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 16)),
                    removal: .opacity.combined(with: .offset(y: -8))
                ))
                .id(state.currentStep == 2 ? "perm-\(permissionIndex)" : "step-\(state.currentStep)")

                Spacer()

                bottomBar
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 28) {
            VStack(spacing: 16) {
                Text("anna")
                    .font(.system(size: 52, weight: .thin))
                    .tracking(8)
                    .foregroundStyle(.white.opacity(0.88))

                Rectangle().fill(.white.opacity(0.08)).frame(width: 32, height: 1)

                Text("your AI friend, right here on your Mac")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(0.3)
            }
        }
    }

    // MARK: - Step 1: Capabilities

    private var capabilitiesStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What Anna can do")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Text("A quick look at how Anna helps you.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
            }

            VStack(spacing: 2) {
                capabilityRow(icon: "waveform", title: "Voice commands",
                              detail: "Hold Right \u{2318} and talk \u{2014} Anna listens, thinks, and acts.")
                capabilityRow(icon: "character.cursor.ibeam", title: "Dictation",
                              detail: "Hold Right \u{2325} to dictate text into any app.")
                capabilityRow(icon: "eye", title: "Screen awareness",
                              detail: "Anna can see your screen and point to what you need.")
                capabilityRow(icon: "bolt.fill", title: "App control",
                              detail: "Open apps, play music, search the web \u{2014} just ask.")
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Step 2: Individual Permission Requests

    private var permissionRequestStep: some View {
        VStack(spacing: 24) {
            if let perm = currentPermission {
                // Header
                VStack(spacing: 6) {
                    Text("Permissions")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                        .tracking(1)
                    Text("\(permissionIndex + 1) of \(permissions.count)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.2))
                }

                // Permission icon + name
                VStack(spacing: 14) {
                    Image(systemName: perm.icon)
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.04), in: Circle())

                    Text(perm.displayName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))

                    if perm.isRequired {
                        Text("Required")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(hex: "FFC764").opacity(0.8))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color(hex: "FFC764").opacity(0.1), in: Capsule())
                    } else {
                        Text("Optional")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.3))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.04), in: Capsule())
                    }
                }

                // Explanation
                Text(perm.reason)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)

                // Status / action
                let status = permissionsViewModel.statusFor(perm)
                if status?.isGranted == true {
                    grantedBadge
                } else {
                    VStack(spacing: 10) {
                        Button {
                            permissionsViewModel.request(perm)
                        } label: {
                            Text("Grant Access")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 8)
                                .background(.white.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        if status?.needsAttention == true {
                            Button {
                                permissionsViewModel.openSettings(for: perm)
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Open System Settings")
                                    Image(systemName: "arrow.up.forward")
                                        .font(.system(size: 9))
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.3))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Progress dots
                HStack(spacing: 6) {
                    ForEach(0..<permissions.count, id: \.self) { i in
                        let kind = permissions[i]
                        let isGranted = permissionsViewModel.statusFor(kind)?.isGranted == true
                        Circle()
                            .fill(
                                i == permissionIndex
                                    ? .white.opacity(0.7)
                                    : isGranted
                                        ? Color(hex: "69D3B0").opacity(0.6)
                                        : .white.opacity(0.12)
                            )
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Step 3: Completion

    private var completionStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color(hex: "69D3B0").opacity(0.7))

            Text("You're all set.")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))

            VStack(spacing: 8) {
                Text("Hold Right \u{2318} anytime to talk to Anna.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                Text("Hold Right \u{2325} to dictate text anywhere.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
            }

            if !permissionsViewModel.allGranted {
                VStack(spacing: 4) {
                    Rectangle().fill(.white.opacity(0.06)).frame(width: 40, height: 1)
                        .padding(.top, 8)
                    Text("Some permissions are still missing. You can grant them later in the Permission Center.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.25))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            // Step indicators
            HStack(spacing: 6) {
                ForEach(0..<OnboardingState.totalSteps, id: \.self) { i in
                    Circle()
                        .fill(i == state.currentStep ? .white.opacity(0.7) : .white.opacity(0.12))
                        .frame(width: 5, height: 5)
                }
            }

            Spacer()

            // Skip / Next actions
            if state.currentStep == 2 {
                if currentPermission?.isRequired == false {
                    Button("Skip") {
                        advancePermission()
                    }
                    .buttonStyle(OnboardingGhostButton())
                }

                let isGranted = currentPermission.flatMap { permissionsViewModel.statusFor($0) }?.isGranted == true
                if isGranted || permissionIndex >= permissions.count {
                    Button(permissionIndex >= permissions.count - 1 ? "Finish" : "Next") {
                        advancePermission()
                    }
                    .buttonStyle(OnboardingPillButton())
                }
            } else if state.currentStep == OnboardingState.totalSteps - 1 {
                Button("Start") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        state.isComplete = true
                    }
                }
                .buttonStyle(OnboardingPillButton())
            } else {
                Button("Continue") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        state.currentStep += 1
                    }
                }
                .buttonStyle(OnboardingPillButton())
            }
        }
    }

    // MARK: - Helpers

    private func advancePermission() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if permissionIndex < permissions.count - 1 {
                permissionIndex += 1
            } else {
                state.currentStep += 1
            }
        }
    }

    private var grantedBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
            Text("Granted")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(Color(hex: "69D3B0"))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(hex: "69D3B0").opacity(0.08), in: Capsule())
    }

    private func capabilityRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
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
