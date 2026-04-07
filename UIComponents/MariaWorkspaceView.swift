import SwiftUI

struct AnnaWorkspaceView: View {
    @ObservedObject var assistantViewModel: AssistantViewModel
    @ObservedObject var permissionsViewModel: PermissionsViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var logger: RuntimeLogger

    @State private var selectedPage: SidebarPage = .assistant

    enum SidebarPage: String, CaseIterable, Identifiable {
        case assistant = "Assistant"
        case permissions = "Permissions"
        case logs = "Logs"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .assistant: return "waveform.circle"
            case .permissions: return "lock.shield"
            case .logs: return "doc.text.magnifyingglass"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        ZStack {
            AnnaPalette.canvas.ignoresSafeArea()

            HStack(spacing: 0) {
                // Sidebar
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(SidebarPage.allCases) { page in
                        sidebarButton(page)
                    }
                    Spacer()
                }
                .padding(10)
                .frame(width: 200)
                .background(AnnaPalette.sidebar)

                // Detail with animated transitions
                ZStack {
                    AnnaPalette.pane

                    Group {
                        switch selectedPage {
                        case .assistant:
                            AssistantView(viewModel: assistantViewModel)
                        case .permissions:
                            PermissionCenterView(viewModel: permissionsViewModel)
                        case .logs:
                            LogsView(logger: logger)
                        case .settings:
                            SettingsView(viewModel: settingsViewModel)
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)).animation(.easeInOut(duration: 0.25)),
                        removal: .opacity.animation(.easeInOut(duration: 0.15))
                    ))
                    .id(selectedPage)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.trailing, 8)
                .padding(.vertical, 8)
            }
        }
        .onAppear {
            // Restore last selected tab
            let saved = settingsViewModel.settings.lastSelectedTab
            if let page = SidebarPage(rawValue: saved.capitalized) {
                selectedPage = page
            }
        }
        .onChange(of: selectedPage) { _, newValue in
            settingsViewModel.settings.lastSelectedTab = newValue.rawValue.lowercased()
            settingsViewModel.persist()
        }
    }

    private func sidebarButton(_ page: SidebarPage) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                selectedPage = page
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: page.icon)
                    .font(.system(size: 14))
                    .frame(width: 20)
                Text(page.rawValue)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                selectedPage == page
                    ? Color.white.opacity(0.08)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .foregroundStyle(selectedPage == page ? .white : .white.opacity(0.6))
        }
        .buttonStyle(.plain)
    }
}
