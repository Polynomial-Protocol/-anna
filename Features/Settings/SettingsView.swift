import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    @State private var cliStatuses: [CLIStatus] = []
    @State private var apiKeyText: String = ""
    @State private var apiKeySaved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))

                section("Interaction") {
                    toggle("Require confirmation for purchases", $viewModel.settings.requiresConfirmationForPurchases)
                    toggle("Reuse successful action routes", $viewModel.settings.autoReuseSuccessfulRoutes)
                }

                section("Voice") {
                    toggle("Let me talk back to you", $viewModel.settings.ttsEnabled)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Speed")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                        HStack(spacing: 8) {
                            Text("Slow")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.3))
                            Slider(value: Binding(
                                get: { viewModel.settings.ttsRate },
                                set: { viewModel.settings.ttsRate = $0; viewModel.persist() }
                            ), in: 0.3...0.65)
                            .tint(.white.opacity(0.3))
                            Text("Fast")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                }

                section("Knowledge") {
                    toggle("Remember things for me", $viewModel.settings.knowledgeBaseEnabled)
                    toggle("Pay attention to what I copy", $viewModel.settings.clipboardCaptureEnabled)
                    Text("I'll remember copied text so I can help you better. Sensitive stuff is always filtered out.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.25))
                        .fixedSize(horizontal: false, vertical: true)
                }

                section("AI Backend") {
                    // Provider picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Provider")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))

                        HStack(spacing: 6) {
                            ForEach(AIProvider.allCases, id: \.self) { provider in
                                let isSelected = viewModel.settings.aiProvider == provider.rawValue
                                let isAvailable = provider.isAPI || cliStatuses.contains(where: { $0.backend.rawValue == provider.rawValue.replacingOccurrences(of: " CLI", with: "") && $0.isInstalled })

                                Button {
                                    viewModel.settings.aiProvider = provider.rawValue
                                    viewModel.persist()
                                    loadAPIKey(for: provider)
                                } label: {
                                    Text(provider.rawValue)
                                        .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .white.opacity(isAvailable ? 0.5 : 0.25))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            isSelected ? Color.white.opacity(0.1) : Color.white.opacity(0.03),
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // API key input (for API providers)
                    let selectedProvider = AIProvider(rawValue: viewModel.settings.aiProvider) ?? .anthropic
                    if selectedProvider.isAPI {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("API Key")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))

                            HStack(spacing: 8) {
                                SecureField("sk-...", text: $apiKeyText)
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

                            let hasKey = APIKeyStore.load(for: selectedProvider) != nil
                            if hasKey {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 9))
                                    Text("Key stored in Keychain")
                                        .font(.system(size: 10))
                                }
                                .foregroundStyle(Color(hex: "69D3B0").opacity(0.7))
                            }

                            Text(selectedProvider == .anthropic
                                ? "Get your API key at console.anthropic.com"
                                : "Get your API key at platform.openai.com")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.25))
                        }
                    }

                    // CLI status (for CLI providers)
                    if selectedProvider.isCLI {
                        let matching = cliStatuses.first(where: { $0.backend.rawValue == selectedProvider.rawValue.replacingOccurrences(of: " CLI", with: "") })
                        if matching?.isInstalled == true {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9))
                                Text("Installed and ready")
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(Color(hex: "69D3B0").opacity(0.7))
                        } else {
                            Text("Not installed. Run:\n\(selectedProvider == .claudeCLI ? "curl -fsSL https://claude.ai/install.sh | sh" : "npm install -g @openai/codex")")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.25))
                                .textSelection(.enabled)
                        }

                        Button {
                            cliStatuses = CLIStatus.detectAll()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise").font(.system(size: 9))
                                Text("Refresh").font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                section("Shortcuts") {
                    shortcutRow("Right \u{2318}", "Agent command")
                    shortcutRow("Right \u{2325}", "Dictation")
                    shortcutRow("\u{2318}\u{21E7}Space", "Text bar")
                }
            }
            .padding(24)
        }
        .onAppear {
            cliStatuses = CLIStatus.detectAll()
            let provider = AIProvider(rawValue: viewModel.settings.aiProvider) ?? .anthropic
            loadAPIKey(for: provider)
        }
    }

    // MARK: - Components

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
                .tracking(1)

            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func toggle(_ label: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: Binding(
            get: { binding.wrappedValue },
            set: { binding.wrappedValue = $0; viewModel.persist() }
        )) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(.white.opacity(0.35))
    }

    private func loadAPIKey(for provider: AIProvider) {
        apiKeyText = APIKeyStore.load(for: provider) ?? ""
        apiKeySaved = false
    }

    private func shortcutRow(_ key: String, _ desc: String) -> some View {
        HStack(spacing: 10) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            Text(desc)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

}
