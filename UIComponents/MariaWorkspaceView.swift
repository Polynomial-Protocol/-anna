import SwiftUI

/// iMessage-inspired chat workspace — matches the original Anna design.
struct AnnaWorkspaceView: View {
    @ObservedObject var assistantViewModel: AssistantViewModel
    @ObservedObject var permissionsViewModel: PermissionsViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var logger: RuntimeLogger
    let knowledgeStore: KnowledgeStore
    let tourGuideStore: TourGuideStore

    @State private var draft: String = ""
    @State private var showSettings = false

    private let canvasColor = Color(red: 0.07, green: 0.07, blue: 0.10)
    private let paneColor = Color(red: 0.10, green: 0.10, blue: 0.14)
    private let sidebarColor = Color(red: 0.08, green: 0.08, blue: 0.11)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                canvasColor.ignoresSafeArea()

                HStack(spacing: 0) {
                    sidebar
                        .frame(width: min(geometry.size.width * 0.35, 320))
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(paneColor).frame(width: 2)
                        }

                    chatPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Anna")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white.opacity(0.94))
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 10)

            Divider().overlay(Color.white.opacity(0.06))

            // Status
            HStack(spacing: 8) {
                Circle()
                    .fill(assistantViewModel.status.color)
                    .frame(width: 7, height: 7)
                Text(assistantViewModel.statusLine)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)

                if assistantViewModel.status == .speaking {
                    Spacer()
                    Button("Stop") { assistantViewModel.stopSpeaking() }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.08), in: Capsule())
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().overlay(Color.white.opacity(0.06))

            // Shortcuts
            VStack(alignment: .leading, spacing: 8) {
                Text("SHORTCUTS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.25))
                    .tracking(1.5)

                shortcutRow("Right \u{2318}", "Voice command")
                shortcutRow("Right \u{2325}", "Dictation")
                shortcutRow("\u{2303}\u{2325}Space", "Smart rewrite")
                shortcutRow("\u{2318}\u{21E7}Space", "Text bar")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().overlay(Color.white.opacity(0.06))

            // Recent actions
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if assistantViewModel.events.isEmpty {
                        Text("Say something to get started")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.25))
                            .padding(.top, 16)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("RECENT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.25))
                            .tracking(1.5)
                            .padding(.top, 4)

                        ForEach(assistantViewModel.events.prefix(15)) { event in
                            SidebarEventRow(event: event)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
        .background(sidebarColor)
    }

    // MARK: - Chat Pane

    private var chatPane: some View {
        VStack(spacing: 0) {
            messagesArea

            Divider().overlay(Color.white.opacity(0.08))

            composer
        }
        .background(paneColor)
    }

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if assistantViewModel.events.isEmpty && assistantViewModel.lastTranscript.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 0) {
                        // Show transcript as user bubble
                        if !assistantViewModel.lastTranscript.isEmpty {
                            chatBubble(
                                text: assistantViewModel.lastTranscript,
                                isUser: true,
                                time: assistantViewModel.lastTranscriptTime
                            )
                            .padding(.top, 28)
                            .id("user-msg")
                        }

                        // Show response as assistant bubble
                        if !assistantViewModel.streamingText.isEmpty {
                            chatBubble(
                                text: assistantViewModel.streamingText,
                                isUser: false,
                                time: assistantViewModel.lastResponseTime
                            )
                            .padding(.top, 16)
                            .id("assistant-msg")
                        }

                        // Show events as assistant messages
                        ForEach(Array(assistantViewModel.events.reversed().enumerated()), id: \.element.id) { index, event in
                            if !event.body.isEmpty {
                                eventBubble(event: event)
                                    .padding(.top, index == 0 && assistantViewModel.streamingText.isEmpty ? 28 : 16)
                                    .id(event.id)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
                }
            }
            .onChange(of: assistantViewModel.streamingText) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("assistant-msg", anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.85, green: 0.18, blue: 0.18).opacity(0.2),
                                     Color(red: 0.85, green: 0.18, blue: 0.18).opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color(red: 0.85, green: 0.18, blue: 0.18).opacity(0.7))
            }
            Text("Start chatting with Anna")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text("Hold Right \u{2318} to talk, or type below.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Chat Bubbles

    private func chatBubble(text: String, isUser: Bool, time: Date?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 80) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(isUser ? .white : .white.opacity(0.82))
                    .textSelection(.enabled)
                    .padding(.horizontal, isUser ? 14 : 0)
                    .padding(.vertical, isUser ? 10 : 4)
                    .background {
                        if isUser {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.30, green: 0.42, blue: 0.90),
                                                 Color(red: 0.24, green: 0.34, blue: 0.78)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                                )
                        }
                    }
                    .frame(maxWidth: isUser ? 480 : .infinity, alignment: isUser ? .trailing : .leading)

                if let time {
                    Text(AssistantViewModel.timeFormatter.string(from: time))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }

    private func eventBubble(event: AssistantEvent) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(event.tone == .success ? Color(red: 0.25, green: 0.75, blue: 0.45)
                              : event.tone == .warning ? Color.orange
                              : Color.red.opacity(0.7))
                        .frame(width: 5, height: 5)
                    Text(event.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }

                // Extract just the response part (after the double newline)
                let parts = event.body.components(separatedBy: "\n\n")
                let displayText = parts.count > 1 ? parts.dropFirst().joined(separator: "\n\n") : event.body
                Text(displayText)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
                    .textSelection(.enabled)

                Text(AssistantViewModel.timeFormatter.string(from: event.timestamp))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 60)
        }
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message Anna...", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.96))
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .onSubmit { sendDraft() }

            Button {
                sendDraft()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? AnyShapeStyle(Color.white.opacity(0.2))
                            : AnyShapeStyle(LinearGradient(
                                colors: [Color(red: 0.35, green: 0.50, blue: 0.95),
                                         Color(red: 0.28, green: 0.40, blue: 0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                              ))
                    )
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Settings Sheet

    private var settingsSheet: some View {
        NavigationStack {
            SettingsView(viewModel: settingsViewModel, tourGuideStore: tourGuideStore)
                .frame(minWidth: 500, minHeight: 400)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showSettings = false }
                    }
                }
        }
    }

    // MARK: - Helpers

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        assistantViewModel.sendText(text)
    }

    private func shortcutRow(_ key: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

// MARK: - Sidebar Event Row

private struct SidebarEventRow: View {
    let event: AssistantEvent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(event.tone == .success ? Color(red: 0.25, green: 0.75, blue: 0.45)
                      : event.tone == .warning ? Color.orange
                      : Color.red.opacity(0.7))
                .frame(width: 5, height: 5)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Text(event.body.prefix(80).description)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(2)
            }

            Spacer()

            Text(timeLabel)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.2))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }

    private var timeLabel: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: event.timestamp, relativeTo: Date())
    }
}
