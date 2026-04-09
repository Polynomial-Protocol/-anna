import SwiftUI

struct AnnaWorkspaceView: View {
    @ObservedObject var assistantViewModel: AssistantViewModel
    @ObservedObject var permissionsViewModel: PermissionsViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var logger: RuntimeLogger
    let knowledgeStore: KnowledgeStore

    @State private var selectedPage: SidebarPage = .assistant

    enum SidebarPage: String, CaseIterable, Identifiable {
        case assistant = "Anna"
        case knowledge = "Knowledge"
        case permissions = "Permissions"
        case logs = "Logs"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .assistant: return "face.smiling"
            case .knowledge: return "brain.head.profile"
            case .permissions: return "lock.shield"
            case .logs: return "text.alignleft"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(spacing: 2) {
                ForEach(SidebarPage.allCases) { page in
                    sidebarItem(page)
                }
                Spacer()
            }
            .padding(6)
            .frame(width: 170)
            .background(Color(red: 0.06, green: 0.06, blue: 0.08))

            // Content
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.10)

                Group {
                    switch selectedPage {
                    case .assistant:
                        AssistantView(viewModel: assistantViewModel)
                    case .knowledge:
                        KnowledgeDumpView(knowledgeStore: knowledgeStore)
                    case .permissions:
                        PermissionCenterView(viewModel: permissionsViewModel)
                    case .logs:
                        LogsView(logger: logger)
                    case .settings:
                        SettingsView(viewModel: settingsViewModel)
                    }
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                .id(selectedPage)
            }
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.08))
        .onAppear {
            let saved = settingsViewModel.settings.lastSelectedTab
            if let page = SidebarPage(rawValue: saved) {
                selectedPage = page
            }
        }
        .onChange(of: selectedPage) { _, newValue in
            settingsViewModel.settings.lastSelectedTab = newValue.rawValue
            settingsViewModel.persist()
        }
    }

    private func sidebarItem(_ page: SidebarPage) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedPage = page }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: page.icon)
                    .font(.system(size: 11))
                    .frame(width: 16)
                Text(page.rawValue)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                selectedPage == page
                    ? Color.white.opacity(0.05)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .foregroundStyle(selectedPage == page ? .white.opacity(0.75) : .white.opacity(0.35))
        }
        .buttonStyle(.plain)
    }
}
