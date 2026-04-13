import SwiftUI
import AVFoundation

// MARK: - Theme (matching original Anna)

private enum Theme {
    static let red = Color(red: 0.839, green: 0.188, blue: 0.192)
    static let ink = Color(red: 0.04, green: 0.04, blue: 0.04)
    static let ink2 = Color(red: 0.27, green: 0.27, blue: 0.27)
    static let ink3 = Color(red: 0.53, green: 0.53, blue: 0.53)
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @Binding var state: OnboardingState
    @ObservedObject var permissionsViewModel: PermissionsViewModel
    @ObservedObject var speechModelViewModel: SpeechModelViewModel
    var ttsService: TTSService

    @State private var cliStatuses: [CLIStatus] = []
    @State private var hasPlayedWelcome = false
    @State private var selectedProvider: AIProvider = .anthropic
    @State private var apiKeyText: String = ""
    @State private var apiKeySaved = false
    private let ambientPlayer = AmbientPadPlayer()

    var body: some View {
        ZStack {
            // Light backdrop
            Color(red: 0.96, green: 0.96, blue: 0.96).ignoresSafeArea()
            LinearGradient(
                colors: [.primary.opacity(0.0), .primary.opacity(0.4), .primary.opacity(0.8), .primary.opacity(0.95)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Theme.red)
                            .frame(width: 10, height: 10)
                        Text("Anna")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.ink)
                    }
                    Spacer()
                }
                .padding(.horizontal, 40)
                .padding(.top, 28)
                .padding(.bottom, 20)

                // Step content
                Group {
                    switch state.currentStep {
                    case 0: welcomeStep
                    case 1: capabilitiesStep
                    case 2: cliCheckStep
                    case 3: permissionsStep
                    default: completionStep
                    }
                }
                .id("step-\(state.currentStep)")
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(x: 30)),
                    removal: .opacity.combined(with: .offset(x: -30))
                ))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // Footer
                VStack(spacing: 20) {
                    // Progress dots
                    HStack(spacing: 6) {
                        ForEach(0..<OnboardingState.totalSteps, id: \.self) { i in
                            Capsule()
                                .fill(i <= state.currentStep ? Theme.red : Theme.ink.opacity(0.12))
                                .frame(width: i == state.currentStep ? 28 : 8, height: 8)
                                .animation(.spring(response: 0.35), value: state.currentStep)
                        }
                    }

                    HStack {
                        if state.currentStep > 0 {
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) { state.currentStep -= 1 }
                            } label: {
                                Text("Back")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.ink2)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.primary.opacity(0.6)))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.primary.opacity(0.8), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()

                        Button {
                            if state.currentStep >= OnboardingState.totalSteps - 1 {
                                state.isComplete = true
                            } else {
                                withAnimation(.easeInOut(duration: 0.25)) { state.currentStep += 1 }
                            }
                        } label: {
                            Text(state.currentStep >= OnboardingState.totalSteps - 1 ? "Get Started" : "Continue")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.red))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return)
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 40)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: 880)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [.primary.opacity(0.55), .primary.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(LinearGradient(colors: [.primary.opacity(0.8), .primary.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 40, x: 0, y: 20)
            .padding(40)
        }
        .frame(minWidth: 960, minHeight: 700)
        .environment(\.colorScheme, .light)
        .onAppear {
            refreshCLI()
            let saved = AppSettings.load().aiProvider
            if let provider = AIProvider(rawValue: saved) {
                selectedProvider = provider
                if provider.isAPI { apiKeyText = APIKeyStore.load(for: provider) ?? "" }
            }
            if !hasPlayedWelcome {
                hasPlayedWelcome = true
                ambientPlayer.play()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    ttsService.speak(Self.welcomeScript)
                }
            }
        }
        .onChange(of: state.currentStep) { _, _ in ttsService.stop() }
        .onChange(of: state.isComplete) { _, completed in if completed { ambientPlayer.stop() } }
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTag("Voice-First AI Agent for macOS")
                .padding(.bottom, 20)

            Text("Your voice.\nYour Mac.\nNo limits.")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .tracking(-2)
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 16)

            Text("Anna turns natural speech into real actions — opening apps, browsing the web, writing text, managing your calendar. All locally processed. All private.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.ink2)
                .lineSpacing(4)
                .frame(maxWidth: 480, alignment: .leading)
                .padding(.bottom, 32)

            HStack(spacing: 12) {
                StatTile(value: "13", unit: "Tools", label: "Built-in actions")
                StatTile(value: "4+", unit: "LLMs", label: "Model providers")
                StatTile(value: "0", unit: "ms", label: "Cloud latency")
                StatTile(value: "100", unit: "%", label: "Private & local")
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Step 1: Capabilities

    private var capabilitiesStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTag("What Anna Can Do")
                .padding(.bottom, 20)

            Text("Voice, vision,\nand action.")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .tracking(-1.5)
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 10)

            Text("Anna listens, sees your screen, and takes real actions on your Mac.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.ink2)
                .lineSpacing(4)
                .padding(.bottom, 28)

            VStack(spacing: 10) {
                capabilityCard(icon: "waveform", title: "Voice Commands", desc: "Hold Right \u{2318} and talk — Anna listens, thinks, and acts.")
                capabilityCard(icon: "character.cursor.ibeam", title: "Dictation", desc: "Hold Right \u{2325} to dictate text into any app.")
                capabilityCard(icon: "eye", title: "Screen Awareness", desc: "Anna sees your screen and points at what you need.")
                capabilityCard(icon: "bolt.fill", title: "App Control", desc: "Open apps, play music, search the web — just ask.")
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Step 2: AI Backend

    private var cliCheckStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTag("Connect Your AI")
                .padding(.bottom, 20)

            Text("Bring your\nown model.")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .tracking(-1.5)
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 10)

            Text("Pick how Anna connects to AI. You can change this anytime in Settings.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.ink2)
                .lineSpacing(4)
                .padding(.bottom, 24)

            VStack(spacing: 8) {
                providerRow(.anthropic, icon: "sparkle", desc: "Best quality. Needs API key.", badge: "Recommended")
                providerRow(.openai, icon: "bubble.left.fill", desc: "GPT-4o. Needs API key.", badge: nil)
                let claudeOK = cliStatuses.first(where: { $0.backend == .claude })?.isInstalled == true
                providerRow(.claudeCLI, icon: "terminal", desc: claudeOK ? "Installed and ready." : "Not installed.", badge: claudeOK ? "Installed" : nil)
            }
            .padding(.bottom, 16)

            if selectedProvider.isAPI {
                VStack(alignment: .leading, spacing: 6) {
                    Text("API Key")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.ink3)
                    HStack(spacing: 8) {
                        TextField("sk-...", text: $apiKeyText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.5)))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.primary.opacity(0.7), lineWidth: 1))
                        Button {
                            APIKeyStore.save(key: apiKeyText, for: selectedProvider)
                            apiKeySaved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { apiKeySaved = false }
                        } label: {
                            Text(apiKeySaved ? "Saved!" : "Save")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(apiKeySaved ? .green : .white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(apiKeySaved ? Color.green.opacity(0.15) : Theme.red, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Step 3: Permissions

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTag("Permissions")
                .padding(.bottom, 20)

            Text("Grant access so\nAnna can help.")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .tracking(-1.5)
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 10)

            Text("These permissions let Anna hear you, read the screen, and type on your behalf.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.ink2)
                .lineSpacing(4)
                .padding(.bottom, 28)

            VStack(spacing: 10) {
                permissionCard(icon: "mic.fill", title: "Microphone", desc: "Voice input and dictation",
                               granted: permissionsViewModel.statusFor(.microphone)?.isGranted ?? false) {
                    AVAudioApplication.requestRecordPermission { _ in
                        Task { @MainActor in permissionsViewModel.refresh() }
                    }
                }
                permissionCard(icon: "hand.raised.fill", title: "Accessibility", desc: "Typing and app control",
                               granted: AXIsProcessTrusted()) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                permissionCard(icon: "rectangle.dashed.badge.record", title: "Screen Recording", desc: "Screenshots and visual guidance",
                               granted: CGPreflightScreenCaptureAccess()) {
                    CGRequestScreenCaptureAccess()
                }
            }

            Text("Permissions refresh automatically when you return from System Settings.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink3)
                .padding(.top, 14)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Step 4: Done

    private var completionStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTag("All Set")
                .padding(.bottom, 20)

            Text("You're ready.\nStart talking.")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .tracking(-2)
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 10)

            Text("Anna lives in your menu bar. Use these shortcuts anytime.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.ink2)
                .lineSpacing(4)
                .padding(.bottom, 32)

            VStack(spacing: 12) {
                shortcutCard(keys: "Right \u{2318}", action: "Agent Mode", desc: "Speak a command, Anna plans and executes")
                shortcutCard(keys: "Right \u{2325}", action: "Dictation", desc: "Your words appear at cursor instantly")
                shortcutCard(keys: "\u{2318}\u{21E7}Space", action: "Text Bar", desc: "Type a command instead of speaking")
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Shared Components

    private func capabilityCard(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.red)
                .frame(width: 36, height: 36)
                .background(Theme.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                Text(desc).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink3)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LinearGradient(colors: [.primary.opacity(0.45), .primary.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(LinearGradient(colors: [.primary.opacity(0.6), .primary.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
    }

    private func providerRow(_ provider: AIProvider, icon: String, desc: String, badge: String?) -> some View {
        let isSelected = selectedProvider == provider
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedProvider = provider
                var settings = AppSettings.load()
                settings.aiProvider = provider.rawValue
                settings.save()
                if provider.isAPI { apiKeyText = APIKeyStore.load(for: provider) ?? ""; apiKeySaved = false }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(isSelected ? Theme.red : Theme.ink3).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.rawValue).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                        if let badge {
                            Text(badge).font(.system(size: 9, weight: .bold)).foregroundStyle(.green).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.green.opacity(0.1), in: Capsule())
                        }
                    }
                    Text(desc).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink3)
                }
                Spacer()
                Circle().fill(isSelected ? Theme.red : .clear).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(isSelected ? Theme.red : Theme.ink.opacity(0.15), lineWidth: 1.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected
                        ? AnyShapeStyle(Theme.red.opacity(0.04))
                        : AnyShapeStyle(LinearGradient(colors: [.primary.opacity(0.45), .primary.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected
                        ? AnyShapeStyle(Theme.red.opacity(0.3))
                        : AnyShapeStyle(LinearGradient(colors: [.primary.opacity(0.6), .primary.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)),
                    lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func permissionCard(icon: String, title: String, desc: String, granted: Bool, onRequest: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.red)
                .frame(width: 36, height: 36).background(Theme.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                Text(desc).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink3)
            }
            Spacer()
            if granted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 14))
                    Text("Granted").font(.system(size: 13, weight: .semibold))
                }.foregroundStyle(.green)
            } else {
                Button { onRequest() } label: {
                    Text("Grant").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Theme.red, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LinearGradient(colors: [.primary.opacity(0.45), .primary.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(LinearGradient(colors: [.primary.opacity(0.6), .primary.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
    }

    private func shortcutCard(keys: String, action: String, desc: String) -> some View {
        HStack(spacing: 14) {
            Text(keys).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                .frame(width: 100).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.45)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.primary.opacity(0.6), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(action).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                Text(desc).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink3)
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private func refreshCLI() {
        cliStatuses = CLIStatus.detectAll()
    }

    static let welcomeScript = "Hey there! I'm Anna, your AI friend on the Mac. Let me walk you through the quick setup, and then we'll be good to go."
}

// MARK: - Shared UI Components

private struct SectionTag: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(2.5)
            .foregroundStyle(Theme.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Theme.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct StatTile: View {
    let value: String
    let unit: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 32, weight: .bold, design: .rounded)).tracking(-1).foregroundStyle(Theme.ink)
            Text(unit).font(.system(size: 13, weight: .bold)).textCase(.uppercase).tracking(0.5).foregroundStyle(Theme.red)
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink3).padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LinearGradient(colors: [.primary.opacity(0.5), .primary.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(LinearGradient(colors: [.primary.opacity(0.7), .primary.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
    }
}
