import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var container: AppContainer

    private var vm: AssistantViewModel { container.assistantViewModel }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status
            HStack(spacing: 6) {
                Circle().fill(vm.status.color).frame(width: 5, height: 5)
                Text(vm.status.displayText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                if vm.isCapturing {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                        .foregroundStyle(vm.status.color)
                        .symbolEffect(.pulse)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 5)

            Rectangle().fill(.white.opacity(0.04)).frame(height: 1)

            HStack(spacing: 0) {
                Text("Right \u{2318} Agent")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.25))
                Spacer()
                Text("Right \u{2325} Dictation")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            Rectangle().fill(.white.opacity(0.04)).frame(height: 1)

            // Recent
            VStack(alignment: .leading, spacing: 3) {
                if vm.events.isEmpty {
                    Text("Nothing yet — say hi!")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.25))
                } else {
                    ForEach(vm.events.prefix(4)) { event in
                        HStack(spacing: 5) {
                            Circle().fill(toneColor(event.tone)).frame(width: 4, height: 4)
                            Text(event.title)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                            Spacer()
                            Text(event.timestamp, style: .time)
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.2))
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

            Rectangle().fill(.white.opacity(0.04)).frame(height: 1)

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    if let w = NSApp.windows.first(where: { $0.title.contains("Anna") && $0.canBecomeMain }) {
                        w.makeKeyAndOrderFront(nil)
                    }
                } label: {
                    Label("Open Anna...", systemImage: "macwindow")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)

                Rectangle().fill(.white.opacity(0.04)).frame(height: 1)

                Button { NSApp.terminate(nil) } label: {
                    Label("Quit", systemImage: "power")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .frame(width: 240)
    }

    private func toneColor(_ tone: AssistantEvent.EventTone) -> Color {
        switch tone {
        case .neutral: return .white.opacity(0.2)
        case .success: return Color(hex: "69D3B0")
        case .warning: return Color(hex: "FFC764")
        case .failure: return .red.opacity(0.7)
        }
    }
}
