import SwiftUI
import AVFoundation

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    @State private var availableVoices: [VoiceInfo] = []
    @State private var previewService = TTSService()
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Voice")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))

                        if !availableVoices.isEmpty {
                            let selectedID = viewModel.settings.ttsVoiceIdentifier.isEmpty
                                ? TTSService.bestAvailableVoiceID()
                                : viewModel.settings.ttsVoiceIdentifier

                            if let current = availableVoices.first(where: { $0.id == selectedID }) {
                                HStack(spacing: 8) {
                                    Text(current.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.7))
                                    Text(current.quality.rawValue)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.35))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(.white.opacity(0.06), in: Capsule())
                                    Spacer()
                                    Button {
                                        if previewService.isSpeaking { previewService.stop() }
                                        else { previewService.speak("Hi, I'm Anna.", rate: viewModel.settings.ttsRate, voiceIdentifier: current.id) }
                                    } label: {
                                        Image(systemName: previewService.isSpeaking ? "stop.fill" : "play.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.white.opacity(0.4))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            voiceList(selectedID: selectedID)
                        }

                        Text("Want me to sound better? Download Premium voices in System Settings > Accessibility > Spoken Content.")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.25))
                            .fixedSize(horizontal: false, vertical: true)
                    }

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
            availableVoices = TTSService.availableVoices()
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

    // MARK: - Voice

    private func voiceList(selectedID: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let groups: [(String, [VoiceInfo])] = [
                ("Premium", availableVoices.filter { $0.quality == .premium }),
                ("Enhanced", availableVoices.filter { $0.quality == .enhanced }),
                ("Default", Array(availableVoices.filter { $0.quality == .default }.prefix(8)))
            ].filter { !$0.1.isEmpty }

            ForEach(groups, id: \.0) { title, voices in
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.top, 4)

                FlowLayout(spacing: 4) {
                    ForEach(voices) { voice in
                        Button {
                            viewModel.settings.ttsVoiceIdentifier = voice.id
                            viewModel.persist()
                        } label: {
                            Text(voice.name)
                                .font(.system(size: 10, weight: voice.id == selectedID ? .semibold : .regular))
                                .foregroundStyle(voice.id == selectedID ? .white.opacity(0.8) : .white.opacity(0.45))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(
                                    voice.id == selectedID ? Color.white.opacity(0.1) : Color.white.opacity(0.04),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (i, pos) in result.positions.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxW = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, totalH: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > maxW && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            positions.append(CGPoint(x: x, y: y))
            rowH = max(rowH, s.height); x += s.width + spacing; totalH = y + rowH
        }
        return (CGSize(width: maxW, height: totalH), positions)
    }
}
