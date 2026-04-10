import SwiftUI

struct OnboardingView: View {
    @Binding var state: OnboardingState
    @ObservedObject var permissionsViewModel: PermissionsViewModel
    @ObservedObject var speechModelViewModel: SpeechModelViewModel
    var ttsService: TTSService

    @State private var appeared = false
    @State private var cliStatuses: [CLIStatus] = []
    @State private var cliChecking = false
    @State private var hasPlayedWelcome = false
    @State private var selectedProvider: AIProvider = .anthropic
    @State private var apiKeyText: String = ""
    @State private var apiKeySaved = false
    private let ambientPlayer = AmbientPadPlayer()

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
                    case 2: cliCheckStep
                    case 3: permissionsStep
                    default: completionStep
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 16)),
                    removal: .opacity.combined(with: .offset(y: -8))
                ))
                .id("step-\(state.currentStep)")

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
            refreshCLI()
            // Load saved provider selection
            let saved = AppSettings.load().aiProvider
            if let provider = AIProvider(rawValue: saved) {
                selectedProvider = provider
                if provider.isAPI { apiKeyText = APIKeyStore.load(for: provider) ?? "" }
            }
            // Play ambient pad + welcome voice on first appearance
            if !hasPlayedWelcome {
                hasPlayedWelcome = true
                ambientPlayer.play()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    ttsService.speak(Self.welcomeScript)
                }
            }
        }
        .onChange(of: state.currentStep) { _, _ in
            ttsService.stop()
        }
        .onChange(of: state.isComplete) { _, completed in
            if completed { ambientPlayer.stop() }
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

                Text("just talk to me anytime \u{2014} I'm here for you")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.22))
                    .padding(.top, 2)
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

    // MARK: - Step 2: Choose AI Backend

    private var cliCheckStep: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.04), in: Circle())

                Text("Choose your AI")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))

                Text("Pick how Anna connects to AI. You can change this anytime in Settings.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            // Provider cards
            VStack(spacing: 6) {
                // API options (recommended)
                Text("WITH API KEY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.25))
                    .tracking(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                providerCard(
                    provider: .anthropic,
                    icon: "sparkle",
                    subtitle: "Best quality. Needs an Anthropic API key.",
                    badge: "Recommended"
                )
                providerCard(
                    provider: .openai,
                    icon: "bubble.left.fill",
                    subtitle: "GPT-4o. Needs an OpenAI API key.",
                    badge: nil
                )

                // CLI options
                Text("WITH CLI TOOL")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.25))
                    .tracking(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)

                let claudeInstalled = cliStatuses.first(where: { $0.backend == .claude })?.isInstalled == true
                let codexInstalled = cliStatuses.first(where: { $0.backend == .codex })?.isInstalled == true

                providerCard(
                    provider: .claudeCLI,
                    icon: "terminal",
                    subtitle: claudeInstalled ? "Installed and ready." : "Not installed.",
                    badge: claudeInstalled ? "Installed" : nil
                )
                providerCard(
                    provider: .codexCLI,
                    icon: "terminal",
                    subtitle: codexInstalled ? "Installed and ready." : "Not installed.",
                    badge: codexInstalled ? "Installed" : nil
                )
            }

            // API key input (shown for API providers)
            if selectedProvider.isAPI {
                VStack(alignment: .leading, spacing: 6) {
                    Text("API Key")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))

                    HStack(spacing: 6) {
                        SecureField(selectedProvider == .anthropic ? "sk-ant-..." : "sk-...", text: $apiKeyText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                        Button {
                            APIKeyStore.save(key: apiKeyText, for: selectedProvider)
                            apiKeySaved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { apiKeySaved = false }
                        } label: {
                            Text(apiKeySaved ? "Saved!" : "Save")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(apiKeySaved ? Color(hex: "69D3B0") : .white.opacity(0.55))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.white.opacity(0.07), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Text(selectedProvider == .anthropic
                        ? "Get your key at console.anthropic.com"
                        : "Get your key at platform.openai.com")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.2))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func providerCard(provider: AIProvider, icon: String, subtitle: String, badge: String?) -> some View {
        let isSelected = selectedProvider == provider

        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedProvider = provider
                // Save selection immediately
                var settings = AppSettings.load()
                settings.aiProvider = provider.rawValue
                settings.save()
                // Load API key if switching to API provider
                if provider.isAPI {
                    apiKeyText = APIKeyStore.load(for: provider) ?? ""
                    apiKeySaved = false
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .white.opacity(0.35))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isSelected ? .white.opacity(0.85) : .white.opacity(0.55))

                        if let badge {
                            Text(badge)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(badge == "Recommended" ? Color(hex: "69D3B0").opacity(0.8) : Color(hex: "69D3B0").opacity(0.7))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color(hex: "69D3B0").opacity(0.1), in: Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.25))
                }

                Spacer()

                Circle()
                    .fill(isSelected ? .white.opacity(0.8) : .clear)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? .white.opacity(0.06) : .white.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isSelected ? .white.opacity(0.1) : .clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 3: Permissions (Grouped)

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Permissions")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Anna needs a few permissions to work. You can adjust these later in Settings.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
            }

            // Required group
            permissionGroup("Required", permissions: PermissionKind.PermissionGroup.required.permissions, accent: Color(hex: "FFC764"))

            // Optional group
            permissionGroup("Optional", permissions: PermissionKind.PermissionGroup.optional.permissions, accent: .white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Step 4: Completion

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

            let requiredMissing = PermissionKind.PermissionGroup.required.permissions
                .contains { permissionsViewModel.statusFor($0)?.isGranted != true }
            let cliMissing = !cliStatuses.contains(where: \.isInstalled)

            if requiredMissing || cliMissing {
                VStack(spacing: 4) {
                    Rectangle().fill(.white.opacity(0.06)).frame(width: 40, height: 1)
                        .padding(.top, 8)
                    Text("Some setup is incomplete. You can finish it later in the Permission Center or Settings.")
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
            HStack(spacing: 6) {
                ForEach(0..<OnboardingState.totalSteps, id: \.self) { i in
                    Circle()
                        .fill(i == state.currentStep ? .white.opacity(0.7) : .white.opacity(0.12))
                        .frame(width: 5, height: 5)
                }
            }

            Spacer()

            if state.currentStep == 2 {
                // CLI step: always allow skip
                Button("Skip") { advance() }
                    .buttonStyle(OnboardingGhostButton())

                if cliStatuses.contains(where: \.isInstalled) {
                    Button("Continue") { advance() }
                        .buttonStyle(OnboardingPillButton())
                }
            } else if state.currentStep == 3 {
                // Permissions step: skip or continue
                Button("Skip") { advance() }
                    .buttonStyle(OnboardingGhostButton())
                Button("Continue") { advance() }
                    .buttonStyle(OnboardingPillButton())
            } else if state.currentStep == OnboardingState.totalSteps - 1 {
                Button("Start") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        state.isComplete = true
                    }
                }
                .buttonStyle(OnboardingPillButton())
            } else {
                Button("Continue") { advance() }
                    .buttonStyle(OnboardingPillButton())
            }
        }
    }

    // MARK: - Welcome Script

    private static let welcomeScript = "Hey, I'm Anna, your AI friend. I live right here on your Mac, and honestly, I'm just happy to be here. Think of me like a friend who's really good with computers. You talk, I listen, and I'll do my best to help. If you ever get stuck or have questions, just ask me, I'm not going anywhere. Let's get you set up, it'll only take a minute."

    // MARK: - Helpers

    private func advance() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if state.currentStep >= OnboardingState.totalSteps - 1 {
                state.isComplete = true
            } else {
                state.currentStep += 1
            }
        }
    }

    private func refreshCLI() {
        cliChecking = true
        DispatchQueue.global().async {
            let statuses = CLIStatus.detectAll()
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.2)) {
                    self.cliStatuses = statuses
                    self.cliChecking = false
                }
            }
        }
    }

    private func permissionGroup(_ title: String, permissions: [PermissionKind], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(accent.opacity(0.7))
                .tracking(1)

            VStack(spacing: 1) {
                ForEach(permissions, id: \.self) { kind in
                    let status = permissionsViewModel.statusFor(kind)
                    HStack(spacing: 10) {
                        Image(systemName: kind.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(kind.displayName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                            Text(kind.reason)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.25))
                                .lineLimit(1)
                        }

                        Spacer()

                        if status?.isGranted == true {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(hex: "69D3B0"))
                        } else {
                            Button {
                                permissionsViewModel.request(kind)
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
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.03))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
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
