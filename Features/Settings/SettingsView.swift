import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    @State private var cliStatuses: [CLIStatus] = []

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
                    ForEach(cliStatuses, id: \.backend) { status in
                        HStack(spacing: 10) {
                            Image(systemName: "terminal")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.35))
                                .frame(width: 16)
                            Text(status.backend.rawValue)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                            Spacer()
                            if status.isInstalled {
                                HStack(spacing: 3) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 9))
                                    Text("Installed")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundStyle(Color(hex: "69D3B0"))
                            } else {
                                Text("Not found")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                        }
                    }
                    Button {
                        cliStatuses = CLIStatus.detectAll()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9))
                            Text("Refresh")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    if !cliStatuses.contains(where: \.isInstalled) {
                        Text("Install Claude Code or Codex for smart features.\nClaude Code: curl -fsSL https://claude.ai/install.sh | sh\nCodex: npm install -g @openai/codex")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.25))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
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
