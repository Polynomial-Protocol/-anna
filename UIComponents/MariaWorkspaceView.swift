import SwiftUI

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
    @State private var currentSessionTurns: [ConversationTurn] = []

    private var canvasColor: Color { AnnaPalette.canvas }
    private var paneColor: Color { AnnaPalette.pane }
    private var sidebarColor: Color { AnnaPalette.sidebar }

    enum SidebarPage: Hashable {
        case chat(UUID?)
        case knowledge
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
                        .overlay(alignment: .trailing) { Rectangle().fill(paneColor).frame(width: 1) }
                    contentArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .preferredColorScheme(colorSchemeFor(settingsViewModel.settings.appTheme))
        .onAppear { refreshChats() }
    }

    private func colorSchemeFor(_ theme: String) -> ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Top fixed section: nav items
            VStack(spacing: 2) {
                sidebarNavItem("Knowledge", icon: "brain.head.profile", color: .orange, page: .knowledge)
                sidebarNavItem("Logs", icon: "doc.text.magnifyingglass", color: .gray, page: .logs)
                sidebarNavItem("Settings", icon: "gearshape", color: Color(red: 0.45, green: 0.55, blue: 0.65), page: .settings)
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider().overlay(AnnaPalette.separator).padding(.horizontal, 8)

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.4))
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.85))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // New chat button
            Button {
                Task {
                    let session = await assistantViewModel.engine.conversationStoreNewSession()
                    chatSessions = await assistantViewModel.engine.allSessions()
                    selectedPage = .chat(session.id)
                    await selectAndLoadSession(session.id)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 11))
                    Text("New Chat")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(.primary.opacity(0.45))
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            // Scrollable chat list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredChats) { session in
                        chatRow(session)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .background(sidebarColor)
    }

    // MARK: - Sidebar Components

    private func chatRow(_ session: ChatSession) -> some View {
        let isSelected: Bool = {
            if case .chat(let id) = selectedPage { return id == session.id }
            return false
        }()
        return Button {
            Task {
                selectedPage = .chat(session.id)
                await selectAndLoadSession(session.id)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 0.35, green: 0.50, blue: 0.95))
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(Color.primary.opacity(isSelected ? 0.95 : 0.7))
                        .lineLimit(1)
                    Text(session.previewText)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.primary.opacity(isSelected ? 0.5 : 0.3))
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)) : nil)
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
        return Button { selectedPage = page } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white) // Always white on colored badge
                    .frame(width: 22, height: 22)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 5))
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Color.primary.opacity(isSelected ? 0.95 : 0.7))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)) : nil)
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
        case .logs:
            LogsView(logger: logger)
        case .settings:
            SettingsView(viewModel: settingsViewModel, tourGuideStore: tourGuideStore, permissionsViewModel: permissionsViewModel)
        }
    }

    // MARK: - Chat Pane

    private var chatPane: some View {
        VStack(spacing: 0) {
            HStack {
                Circle().fill(assistantViewModel.status.color).frame(width: 7, height: 7)
                Text(assistantViewModel.statusLine)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.55))
                    .lineLimit(1)
                Spacer()
                if assistantViewModel.isInTourMode {
                    Button("Stop Tour") { assistantViewModel.stopTour() }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.red.opacity(0.7))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.red.opacity(0.1), in: Capsule())
                        .buttonStyle(.plain)
                } else if assistantViewModel.status == .speaking {
                    Button("Stop") { assistantViewModel.stopSpeaking() }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.6))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.primary.opacity(0.08), in: Capsule())
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider().overlay(AnnaPalette.separator)

            messagesArea
            Divider().overlay(AnnaPalette.separator)
            composer
        }
        .background(paneColor)
    }

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                let visibleTurns = currentSessionTurns.filter { !$0.isInternal }
                if visibleTurns.isEmpty && assistantViewModel.streamingText.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(visibleTurns.enumerated()), id: \.element.id) { index, turn in
                            chatBubble(text: turn.content, isUser: turn.role == .user, time: turn.timestamp)
                                .padding(.top, index == 0 ? 20 : (turn.role == (index > 0 ? visibleTurns[index - 1].role : turn.role) ? 8 : 16))
                                .id(turn.id)
                        }
                        if !assistantViewModel.streamingText.isEmpty {
                            chatBubble(text: assistantViewModel.streamingText, isUser: false, time: nil)
                                .padding(.top, 16).id("streaming")
                        }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 16)
                }
            }
            .onChange(of: assistantViewModel.streamingText) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("streaming", anchor: .bottom) }
            }
            .onChange(of: assistantViewModel.lastResponseTime) { _, _ in loadCurrentSessionTurns() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(red: 0.85, green: 0.18, blue: 0.18).opacity(0.2), Color(red: 0.85, green: 0.18, blue: 0.18).opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 56, height: 56)
                Image(systemName: "waveform.circle.fill").font(.system(size: 30)).foregroundStyle(Color(red: 0.85, green: 0.18, blue: 0.18).opacity(0.7))
            }
            Text("Start chatting with Anna").font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary.opacity(0.7))
            Text("Hold Right \u{2318} to talk, or type below.").font(.system(size: 13)).foregroundStyle(.primary.opacity(0.4))
        }
        .frame(maxWidth: .infinity).padding(.top, 80)
    }

    // MARK: - Chat Bubbles

    private func chatBubble(text: String, isUser: Bool, time: Date?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 80) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(text).font(.system(size: 14)).foregroundStyle(isUser ? .white : .primary.opacity(0.82)).textSelection(.enabled)
                    .padding(.horizontal, isUser ? 14 : 0).padding(.vertical, isUser ? 10 : 4)
                    .background {
                        if isUser {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(LinearGradient(colors: [AnnaPalette.userGradientStart, AnnaPalette.userGradientEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                        }
                    }
                    .frame(maxWidth: isUser ? 480 : .infinity, alignment: isUser ? .trailing : .leading)
                if let time {
                    Text(AssistantViewModel.timeFormatter.string(from: time)).font(.system(size: 10)).foregroundStyle(.primary.opacity(0.25))
                }
            }
            if !isUser { Spacer(minLength: 60) }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message Anna...", text: $draft)
                .textFieldStyle(.plain).font(.system(size: 14)).foregroundStyle(.primary.opacity(0.96))
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.primary.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                .onSubmit { sendDraft() }
            Button { sendDraft() } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 28))
                    .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? AnyShapeStyle(Color.primary.opacity(0.2))
                        : AnyShapeStyle(LinearGradient(colors: [Color(red: 0.35, green: 0.50, blue: 0.95), Color(red: 0.28, green: 0.40, blue: 0.85)], startPoint: .top, endPoint: .bottom)))
            }.buttonStyle(.plain).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
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
                await selectAndLoadSession(chatSessions.first?.id)
            }
            loadCurrentSessionTurns()
        }
    }

    private func loadCurrentSessionTurns() {
        Task { currentSessionTurns = await assistantViewModel.engine.currentSessionTurns() }
    }

    private func selectAndLoadSession(_ id: UUID?) async {
        guard let id else { return }
        await assistantViewModel.engine.selectSession(id)
        currentSessionTurns = await assistantViewModel.engine.currentSessionTurns()
        await MainActor.run {
            assistantViewModel.streamingText = ""
            assistantViewModel.lastTranscript = ""
        }
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        assistantViewModel.sendText(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { loadCurrentSessionTurns() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { refreshChats(); loadCurrentSessionTurns() }
    }
}
