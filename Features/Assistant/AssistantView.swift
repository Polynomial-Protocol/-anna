import SwiftUI

struct AssistantView: View {
    @ObservedObject var viewModel: AssistantViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 10) {
                    Text("anna")
                        .font(.system(size: 32, weight: .thin))
                        .tracking(4)
                        .foregroundStyle(.primary.opacity(0.85))

                    Text("Your AI friend, always here.")
                        .font(.system(size: 14))
                        .foregroundStyle(.primary.opacity(0.4))
                }

                // Status
                HStack(spacing: 8) {
                    Circle()
                        .fill(viewModel.status.color)
                        .frame(width: 6, height: 6)
                    Text(viewModel.statusLine)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.6))

                    if viewModel.status == .speaking {
                        Button("Stop") { viewModel.stopSpeaking() }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.5))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.primary.opacity(0.07), in: Capsule())
                            .buttonStyle(.plain)
                    }
                }

                // Shortcuts
                HStack(spacing: 16) {
                    shortcut("Right \u{2318}", "Agent")
                    shortcut("Right \u{2325}", "Dictation")
                    shortcut("\u{2318}\u{21E7}Space", "Text Bar")
                }

                // Transcript
                if !viewModel.lastTranscript.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("You")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.primary.opacity(0.35))
                            Spacer()
                            if let time = viewModel.lastTranscriptTime {
                                Text(AssistantViewModel.timeFormatter.string(from: time))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.primary.opacity(0.25))
                            }
                        }
                        Text(viewModel.lastTranscript)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.8))
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                // Response
                if !viewModel.streamingText.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Anna")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.primary.opacity(0.35))
                            Spacer()
                            if let time = viewModel.lastResponseTime {
                                Text(AssistantViewModel.timeFormatter.string(from: time))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.primary.opacity(0.25))
                            }
                        }
                        Text(viewModel.streamingText)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.7))
                            .animation(.easeIn(duration: 0.08), value: viewModel.streamingText)
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Recent actions
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.35))
                        .tracking(0.5)

                    if viewModel.events.isEmpty {
                        Text("Nothing yet — say something!")
                            .font(.system(size: 12))
                            .foregroundStyle(.primary.opacity(0.25))
                    } else {
                        ForEach(viewModel.events) { event in
                            EventRow(event: event)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func shortcut(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.3))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(0.4))
        }
    }
}
