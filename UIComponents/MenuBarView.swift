import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var container: AppContainer

    private var vm: AssistantViewModel { container.assistantViewModel }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusSection
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider().opacity(0.06)

            HStack(spacing: 0) {
                Text("Right ⌘ Agent")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("Right ⌥ Dictation")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            Divider().opacity(0.06)

            recentActivity
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

            Divider().opacity(0.06)

            footerActions
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .frame(width: 280)
    }

    private var statusSection: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(vm.status.color)
                .frame(width: 8, height: 8)

            Text(vm.status.displayText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()

            if vm.isCapturing {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundStyle(vm.status.color)
                    .symbolEffect(.pulse)
            }
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent Activity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if vm.events.isEmpty {
                Text("No actions yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(vm.events.prefix(5)) { event in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(toneColor(event.tone))
                            .frame(width: 6, height: 6)
                        Text(event.title)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text(event.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var footerActions: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !vm.lastTranscript.isEmpty {
                Button {
                } label: {
                    Label("Undo Last Text Insert", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }

            Button {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: {
                    $0.title.contains("Anna") && $0.canBecomeMain
                }) {
                    window.makeKeyAndOrderFront(nil)
                }
            } label: {
                Label("Open Anna...", systemImage: "macwindow")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)

            Divider().opacity(0.06)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Anna", systemImage: "power")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
        }
    }

    private func toneColor(_ tone: AssistantEvent.EventTone) -> Color {
        switch tone {
        case .neutral: return .secondary
        case .success: return AnnaPalette.mint
        case .warning: return AnnaPalette.warning
        case .failure: return .red
        }
    }
}
