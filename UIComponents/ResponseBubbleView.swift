import SwiftUI
import AppKit

// MARK: - Floating NSPanel

final class ResponseBubblePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Controller

@MainActor
final class ResponseBubbleController: ObservableObject {
    @Published var isVisible = false

    private var panel: ResponseBubblePanel?
    private let panelWidth: CGFloat = 360
    private let panelHeight: CGFloat = 260

    func show(viewModel: AssistantViewModel) {
        guard panel == nil else {
            panel?.orderFront(nil)
            isVisible = true
            return
        }

        let frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        let newPanel = ResponseBubblePanel(contentRect: frame)
        newPanel.contentView = NSHostingView(rootView: ResponseBubbleContent(viewModel: viewModel))

        let screen = NSScreen.main ?? NSScreen.screens.first
        if let sf = screen?.visibleFrame {
            newPanel.setFrameOrigin(NSPoint(x: sf.maxX - panelWidth - 16, y: sf.maxY - panelHeight - 8))
        }

        newPanel.alphaValue = 0
        newPanel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            newPanel.animator().alphaValue = 1.0
        }

        panel = newPanel
        isVisible = true
    }

    func hide() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            p.orderOut(nil); p.close(); self?.panel = nil
        })
        isVisible = false
    }
}

// MARK: - Content

struct ResponseBubbleContent: View {
    @ObservedObject var viewModel: AssistantViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.status.color)
                    .frame(width: 6, height: 6)
                Text(viewModel.status.displayText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                if viewModel.isCapturing {
                    Image(systemName: "waveform")
                        .font(.system(size: 12))
                        .foregroundStyle(viewModel.status.color)
                        .symbolEffect(.pulse)
                }
                if viewModel.status == .speaking {
                    Button { viewModel.stopSpeaking() } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Rectangle().fill(.white.opacity(0.04)).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if viewModel.isCapturing {
                        HStack(spacing: 8) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.red.opacity(0.7))
                                .symbolEffect(.pulse)
                            Text(viewModel.activeMode == .assistantCommand ? "I'm listening..." : "Go ahead, I'll type...")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }

                    if !viewModel.lastTranscript.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("You")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.3))
                            Text(viewModel.lastTranscript)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }

                    if !viewModel.streamingText.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Anna")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.3))
                            Text(viewModel.streamingText)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.65))
                                .animation(.easeIn(duration: 0.05), value: viewModel.streamingText)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }

                    if let event = viewModel.events.first, viewModel.streamingText.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(toneColor(event.tone))
                                .frame(width: 5, height: 5)
                                .padding(.top, 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                                Text(event.body)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.45))
                                    .lineLimit(3)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 360, height: 260)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.06), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 16)
        )
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
