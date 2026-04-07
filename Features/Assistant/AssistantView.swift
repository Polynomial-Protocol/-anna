import SwiftUI

struct AssistantView: View {
    @ObservedObject var viewModel: AssistantViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack(alignment: .top, spacing: 18) {
                    assistantHero
                    readinessPanel
                }

                actionTimeline
            }
            .padding(28)
        }
        .background(AnnaPalette.pane)
    }

    private var assistantHero: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Anna")
                .font(.system(size: 54, weight: .bold, design: .serif))
                .foregroundStyle(.white.opacity(0.92))

            Text("Your private Mac assistant that helps you get things done, teaches you how apps work, and guides you visually with on-screen pointers.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: 540, alignment: .leading)

            HStack(spacing: 24) {
                shortcutHint(key: "Right ⌘", label: "Agent", color: .red)
                shortcutHint(key: "Right ⌥", label: "Dictation", color: .blue)
                shortcutHint(key: "⌘⇧Space", label: "Text Bar", color: .orange)
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.status.color)
                    .frame(width: 8, height: 8)
                Text(viewModel.statusLine)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))

                if viewModel.status == .speaking {
                    Button("Stop") {
                        viewModel.stopSpeaking()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if !viewModel.lastTranscript.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Last transcript")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        if let time = viewModel.lastTranscriptTime {
                            Text(AssistantViewModel.timeFormatter.string(from: time))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    Text(viewModel.lastTranscript)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )
            }

            // Streaming response display
            if !viewModel.streamingText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Anna")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.purple.opacity(0.8))
                        Spacer()
                        if let time = viewModel.lastResponseTime {
                            Text(AssistantViewModel.timeFormatter.string(from: time))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    Text(viewModel.streamingText)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.85))
                        .animation(.easeIn(duration: 0.1), value: viewModel.streamingText)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.purple.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.purple.opacity(0.2), lineWidth: 0.5)
                        )
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shortcutHint(key: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var readinessPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Readiness")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white.opacity(0.92))

            StatusPill(text: viewModel.refreshPermissionsSummary(), color: AnnaPalette.mint)
            StatusPill(text: "Purchases require review", color: AnnaPalette.warning)
            StatusPill(text: "Voice + Visual Guidance", color: AnnaPalette.copper)

            Divider().overlay(Color.white.opacity(0.06))

            Text("Hold Right ⌘ to give a command. Hold Right ⌥ to dictate into the focused field. Press ⌘⇧Space for the text bar. Anna will speak responses and point at UI elements to guide you.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
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
        .frame(width: 320)
    }

    private var actionTimeline: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recent Actions")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white.opacity(0.92))

            if viewModel.events.isEmpty {
                Text("Your first actions will appear here with transcripts, execution summaries, and confirmation gates.")
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                ForEach(viewModel.events) { event in
                    EventRow(event: event)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AnnaPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}
