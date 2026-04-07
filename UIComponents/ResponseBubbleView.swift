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
    private let panelWidth: CGFloat = 390
    private let panelHeight: CGFloat = 300

    func show(viewModel: AssistantViewModel) {
        guard panel == nil else {
            panel?.orderFront(nil)
            isVisible = true
            return
        }

        let frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        let newPanel = ResponseBubblePanel(contentRect: frame)

        let hostView = NSHostingView(
            rootView: ResponseBubbleContent(viewModel: viewModel)
        )
        newPanel.contentView = hostView

        // Position near top-right of the current screen (multi-monitor aware)
        let screen = NSScreen.main ?? NSScreen.screens.first
        if let screenFrame = screen?.visibleFrame {
            let x = screenFrame.maxX - panelWidth - 16
            let y = screenFrame.maxY - panelHeight - 8
            newPanel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Animate in
        newPanel.alphaValue = 0
        newPanel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            newPanel.animator().alphaValue = 1.0
        }

        panel = newPanel
        isVisible = true
    }

    func hide() {
        guard let existingPanel = panel else { return }

        // Animate out
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            existingPanel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            existingPanel.orderOut(nil)
            existingPanel.close()
            self?.panel = nil
        })
        isVisible = false
    }
}

// MARK: - Bubble Content View

struct ResponseBubbleContent: View {
    @ObservedObject var viewModel: AssistantViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status pill
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.status.color)
                    .frame(width: 8, height: 8)

                Text(viewModel.status.displayText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))

                Spacer()

                if viewModel.isCapturing {
                    Image(systemName: "waveform")
                        .font(.system(size: 14))
                        .foregroundStyle(viewModel.status.color)
                        .symbolEffect(.pulse)
                }

                if viewModel.status == .speaking {
                    Button {
                        viewModel.stopSpeaking()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().overlay(Color.white.opacity(0.06))

            // Content area
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if viewModel.isCapturing {
                        listeningIndicator
                    }

                    if !viewModel.lastTranscript.isEmpty {
                        transcriptBubble
                    }

                    // Streaming response
                    if !viewModel.streamingText.isEmpty {
                        streamingResponseBubble
                    }

                    // Last event result
                    if let event = viewModel.events.first, viewModel.streamingText.isEmpty {
                        resultBubble(event)
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 390, height: 300)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AnnaPalette.pane)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.35), radius: 20)
        )
    }

    private var listeningIndicator: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 16))
                .foregroundStyle(.red)
                .symbolEffect(.pulse)

            Text(viewModel.activeMode == .assistantCommand ? "Listening for command..." : "Listening for dictation...")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private var transcriptBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("You said:")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if let time = viewModel.lastTranscriptTime {
                    Text(AssistantViewModel.timeFormatter.string(from: time))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }

            Text(viewModel.lastTranscript)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(
                    colors: [AnnaPalette.userGradientStart, AnnaPalette.userGradientEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        )
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var streamingResponseBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.purple)
                Text("Anna")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.purple.opacity(0.8))
                Spacer()
                if let time = viewModel.lastResponseTime {
                    Text(AssistantViewModel.timeFormatter.string(from: time))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }

            Text(viewModel.streamingText)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
                .animation(.easeIn(duration: 0.05), value: viewModel.streamingText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.purple.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.purple.opacity(0.2), lineWidth: 0.5)
                )
        )
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func resultBubble(_ event: AssistantEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(toneColor(event.tone))
                    .frame(width: 6, height: 6)
                Text(event.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(AssistantViewModel.timeFormatter.string(from: event.timestamp))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }

            Text(event.body)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
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
