import SwiftUI

/// Apple Music-inspired workspace with sectioned sidebar.
struct AnnaWorkspaceView: View {
    @ObservedObject var assistantViewModel: AssistantViewModel
    @ObservedObject var permissionsViewModel: PermissionsViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var logger: RuntimeLogger
    let knowledgeStore: KnowledgeStore
    let tourGuideStore: TourGuideStore

    @State private var draft: String = ""
    @State private var searchText: String = ""
    @State private var selectedPage: SidebarPage = .chat(nil)
    @State private var chatSessions: [ChatSession] = []

    private let canvasColor = Color(red: 0.07, green: 0.07, blue: 0.10)
    private let paneColor = Color(red: 0.10, green: 0.10, blue: 0.14)
    private let sidebarColor = Color(red: 0.08, green: 0.08, blue: 0.11)

    enum SidebarPage: Hashable {
        case chat(UUID?)
        case knowledge
        case permissions
        case logs
        case settings
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                canvasColor.ignoresSafeArea()

                HStack(spacing: 0) {
                    sidebar
                        .frame(width: min(geometry.size.width * 0.3, 260))
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(paneColor).frame(width: 1)
                        }

                    contentArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .onAppear { refreshChats() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Chats section
                    sidebarSection("Chats") {
                        // New chat button
                        Button {
                            Task {
                                let session = await assistantViewModel.engine.conversationStoreNewSession()
                                refreshChats()
                                selectedPage = .chat(session.id)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 12))
                                Text("New Chat")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)

                        // Chat list
                        let filtered = filteredChats
                        if filtered.isEmpty {
                            Text("No chats yet")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.25))
                        } else {
                            ForEach(filtered) { session in
                                chatRow(session)
                            }
                        }
                    }

                    // Library section
                    sidebarSection("Library") {
                        sidebarNavItem("Knowledge", icon: "brain.head.profile", color: .orange, page: .knowledge)
                        sidebarNavItem("Permissions", icon: "lock.shield", color: .green, page: .permissions)
                        sidebarNavItem("Logs", icon: "doc.text.magnifyingglass", color: .gray, page: .logs)
                    }

                    // Settings
                    sidebarSection("") {
                        sidebarNavItem("Settings", icon: "gearshape", color: .gray, page: .settings)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .background(sidebarColor)
    }

    // MARK: - Sidebar Components

    private func sidebarSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
                    .tracking(0.5)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 2)
            }
            content()
        }
    }

    private func chatRow(_ session: ChatSession) -> some View {
        let isSelected: Bool = {
            if case .chat(let id) = selectedPage { return id == session.id }
            return false
        }()

        return Button {
            Task {
                await assistantViewModel.engine.selectSession(session.id)
                selectedPage = .chat(session.id)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 0.35, green: 0.50, blue: 0.95))
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .white.opacity(0.95) : .white.opacity(0.7))
                        .lineLimit(1)
                    Text(session.previewText)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(isSelected ? 0.5 : 0.3))
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.08))
                    : nil
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete Chat", role: .destructive) {
                Task {
                    await assistantViewModel.engine.deleteSession(session.id)
                    refreshChats()
                    if case .chat(let id) = selectedPage, id == session.id {
                        selectedPage = .chat(chatSessions.first?.id)
                    }
                }
            }
        }
    }

    private func sidebarNavItem(_ label: String, icon: String, color: Color, page: SidebarPage) -> some View {
        let isSelected = selectedPage == page

        return Button {
            selectedPage = page
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 5))
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white.opacity(0.95) : .white.opacity(0.7))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                isSelected
                    ? RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.08))
                    : nil
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch selectedPage {
        case .chat:
            chatPane
        case .knowledge:
            KnowledgeDumpView(knowledgeStore: knowledgeStore)
        case .permissions:
            PermissionCenterView(viewModel: permissionsViewModel)
        case .logs:
            LogsView(logger: logger)
        case .settings:
            SettingsView(viewModel: settingsViewModel, tourGuideStore: tourGuideStore)
        }
    }

    // MARK: - Chat Pane

    private var chatPane: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill(assistantViewModel.status.color)
                    .frame(width: 7, height: 7)
                Text(assistantViewModel.statusLine)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                Spacer()
                if assistantViewModel.status == .speaking {
                    Button("Stop") { assistantViewModel.stopSpeaking() }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.08), in: Capsule())
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().overlay(Color.white.opacity(0.06))

            // Messages
            messagesArea

            Divider().overlay(Color.white.opacity(0.08))

            // Composer
            composer
        }
        .background(paneColor)
    }

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if assistantViewModel.lastTranscript.isEmpty && assistantViewModel.events.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 0) {
                        if !assistantViewModel.lastTranscript.isEmpty {
                            chatBubble(text: assistantViewModel.lastTranscript, isUser: true, time: assistantViewModel.lastTranscriptTime)
                                .padding(.top, 28)
                                .id("user-msg")
                        }
                        if !assistantViewModel.streamingText.isEmpty {
                            chatBubble(text: assistantViewModel.streamingText, isUser: false, time: assistantViewModel.lastResponseTime)
                                .padding(.top, 16)
                                .id("assistant-msg")
                        }
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
                            startPoint: .topLeading, endPoint: .bottomTrailing
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
                                .fill(LinearGradient(
                                    colors: [Color(red: 0.30, green: 0.42, blue: 0.90), Color(red: 0.24, green: 0.34, blue: 0.78)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
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
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                .onSubmit { sendDraft() }

            Button { sendDraft() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? AnyShapeStyle(Color.white.opacity(0.2))
                            : AnyShapeStyle(LinearGradient(
                                colors: [Color(red: 0.35, green: 0.50, blue: 0.95), Color(red: 0.28, green: 0.40, blue: 0.85)],
                                startPoint: .top, endPoint: .bottom))
                    )
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Helpers

    private var filteredChats: [ChatSession] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sorted = chatSessions.sorted { $0.updatedAt > $1.updatedAt }
        guard !q.isEmpty else { return sorted }
        return sorted.filter { $0.title.lowercased().contains(q) || $0.previewText.lowercased().contains(q) }
    }

    private func refreshChats() {
        Task {
            chatSessions = await assistantViewModel.engine.allSessions()
            if chatSessions.isEmpty {
                let session = await assistantViewModel.engine.conversationStoreNewSession()
                chatSessions = [session]
                selectedPage = .chat(session.id)
            } else if case .chat(nil) = selectedPage {
                selectedPage = .chat(chatSessions.first?.id)
            }
        }
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        assistantViewModel.sendText(text)
        // Refresh chat list after a brief delay so new title appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { refreshChats() }
    }
}
