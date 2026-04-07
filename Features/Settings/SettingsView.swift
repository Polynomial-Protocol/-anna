import SwiftUI
import AVFoundation

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    @State private var availableVoices: [VoiceInfo] = []
    @State private var previewService = TTSService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))

                // Interaction section
                settingsSection(title: "Interaction") {
                    settingsToggle(
                        "Require confirmation for purchases",
                        isOn: Binding(
                            get: { viewModel.settings.requiresConfirmationForPurchases },
                            set: {
                                viewModel.settings.requiresConfirmationForPurchases = $0
                                viewModel.persist()
                            }
                        )
                    )

                    settingsToggle(
                        "Reuse successful action routes",
                        isOn: Binding(
                            get: { viewModel.settings.autoReuseSuccessfulRoutes },
                            set: {
                                viewModel.settings.autoReuseSuccessfulRoutes = $0
                                viewModel.persist()
                            }
                        )
                    )
                }

                // Voice section
                settingsSection(title: "Voice") {
                    settingsToggle(
                        "Speak responses aloud",
                        isOn: Binding(
                            get: { viewModel.settings.ttsEnabled },
                            set: {
                                viewModel.settings.ttsEnabled = $0
                                viewModel.persist()
                            }
                        )
                    )

                    // Voice picker
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Voice")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))

                        if availableVoices.isEmpty {
                            Text("Loading voices...")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.4))
                        } else {
                            let selectedID = viewModel.settings.ttsVoiceIdentifier.isEmpty
                                ? TTSService.bestAvailableVoiceID()
                                : viewModel.settings.ttsVoiceIdentifier

                            // Currently selected voice info
                            if let current = availableVoices.first(where: { $0.id == selectedID }) {
                                HStack(spacing: 8) {
                                    voiceBadge(current)
                                    Spacer()
                                    Button {
                                        previewVoice(current)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: previewService.isSpeaking ? "stop.fill" : "play.fill")
                                                .font(.system(size: 10))
                                            Text(previewService.isSpeaking ? "Stop" : "Preview")
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(AnnaPalette.accent.opacity(0.2), in: Capsule())
                                        .foregroundStyle(AnnaPalette.accent)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            // Voice list grouped by quality
                            voiceList(selectedID: selectedID)
                        }

                        Text("For the best voices, go to System Settings > Accessibility > Spoken Content > System Voice > Manage Voices and download Premium or Enhanced voices.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Speech rate
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Speech rate")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                        HStack {
                            Text("Slow")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                            Slider(value: Binding(
                                get: { viewModel.settings.ttsRate },
                                set: {
                                    viewModel.settings.ttsRate = $0
                                    viewModel.persist()
                                }
                            ), in: 0.3...0.65)
                            .tint(AnnaPalette.accent)
                            Text("Fast")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }

                // Integration section
                settingsSection(title: "Integration") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preferred browser")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(viewModel.settings.preferredBrowserBundleID)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI backend")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("Claude CLI (local) — uses Claude Sonnet for reasoning")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Speech engine")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("Apple Speech Recognition (on-device)")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                // Keyboard shortcuts section
                settingsSection(title: "Keyboard Shortcuts") {
                    shortcutRow("Right ⌘ (hold)", "Voice agent command")
                    shortcutRow("Right ⌥ (hold)", "Dictation mode")
                    shortcutRow("⌘ ⇧ Space", "Toggle text bar")
                }
            }
            .padding(28)
        }
        .background(AnnaPalette.pane)
        .onAppear {
            availableVoices = TTSService.availableVoices()
        }
    }

    // MARK: - Voice List

    private func voiceList(selectedID: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let premiumVoices = availableVoices.filter { $0.quality == .premium }
            let enhancedVoices = availableVoices.filter { $0.quality == .enhanced }
            let defaultVoices = availableVoices.filter { $0.quality == .default }

            if !premiumVoices.isEmpty {
                voiceGroup("Premium", voices: premiumVoices, selectedID: selectedID)
            }
            if !enhancedVoices.isEmpty {
                voiceGroup("Enhanced", voices: enhancedVoices, selectedID: selectedID)
            }
            if !defaultVoices.isEmpty {
                voiceGroup("Default", voices: defaultVoices.prefix(8).map { $0 }, selectedID: selectedID)
            }
        }
    }

    private func voiceGroup(_ title: String, voices: [VoiceInfo], selectedID: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 6)

            FlowLayout(spacing: 6) {
                ForEach(voices) { voice in
                    Button {
                        viewModel.settings.ttsVoiceIdentifier = voice.id
                        viewModel.persist()
                    } label: {
                        voiceChip(voice, isSelected: voice.id == selectedID)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func voiceChip(_ voice: VoiceInfo, isSelected: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: voice.gender == .female ? "person.fill" : voice.gender == .male ? "person.fill" : "person")
                .font(.system(size: 9))
            Text(voice.name)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            isSelected
                ? AnnaPalette.accent.opacity(0.25)
                : Color.white.opacity(0.06),
            in: Capsule()
        )
        .overlay(
            Capsule().stroke(
                isSelected ? AnnaPalette.accent.opacity(0.6) : Color.white.opacity(0.08),
                lineWidth: 0.5
            )
        )
        .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
    }

    private func voiceBadge(_ voice: VoiceInfo) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 11))
                .foregroundStyle(AnnaPalette.accent)
            Text(voice.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text(voice.quality.rawValue)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(qualityColor(voice.quality))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(qualityColor(voice.quality).opacity(0.15), in: Capsule())
            Text(voice.gender.rawValue)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private func qualityColor(_ quality: VoiceInfo.VoiceQuality) -> Color {
        switch quality {
        case .premium: return AnnaPalette.mint
        case .enhanced: return AnnaPalette.copper
        case .default: return .secondary
        }
    }

    private func previewVoice(_ voice: VoiceInfo) {
        if previewService.isSpeaking {
            previewService.stop()
        } else {
            previewService.speak(
                "Hi, I'm Anna, your Mac assistant. I can help you get things done and teach you how apps work.",
                rate: viewModel.settings.ttsRate,
                voiceIdentifier: voice.id
            )
        }
    }

    // MARK: - Shared Components

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))

            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AnnaPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
    }

    private func settingsToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))
        }
        .toggleStyle(.switch)
        .tint(AnnaPalette.accent)
    }

    private func shortcutRow(_ key: String, _ description: String) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(description)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

// MARK: - Flow Layout for Voice Chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
