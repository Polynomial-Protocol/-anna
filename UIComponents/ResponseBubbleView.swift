import SwiftUI
import AppKit

// MARK: - Floating NSPanel (borderless, transparent, click-through)

final class ResponseBubblePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true  // Click-through: never blocks interaction
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Controller

@MainActor
final class ResponseBubbleController: ObservableObject {
    @Published var isVisible = false

    private var panel: ResponseBubblePanel?
    private let panelWidth: CGFloat = 480
    private let panelHeight: CGFloat = 200

    func show(viewModel: AssistantViewModel) {
        if panel != nil {
            panel?.orderFront(nil)
            isVisible = true
            return
        }

        let frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        let newPanel = ResponseBubblePanel(contentRect: frame)
        newPanel.contentView = NSHostingView(
            rootView: ResponseOverlayContent(viewModel: viewModel)
                .frame(width: panelWidth, height: panelHeight)
        )

        // Position: bottom-center of main screen
        if let sf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            let x = sf.midX - panelWidth / 2
            let y = sf.minY + 60
            newPanel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        newPanel.alphaValue = 0
        newPanel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            newPanel.animator().alphaValue = 1.0
        }

        panel = newPanel
        isVisible = true
    }

    func hide() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            p.orderOut(nil)
            p.close()
            self?.panel = nil
        })
        isVisible = false
    }
}

// MARK: - Overlay Content (minimal floating text)

struct ResponseOverlayContent: View {
    @ObservedObject var viewModel: AssistantViewModel
    @State private var showResponse = false
    @State private var previousStreamingText = ""

    var body: some View {
        VStack(spacing: 8) {
            Spacer()

            // Response text (auto-dismiss after display)
            if showResponse && !viewModel.streamingText.isEmpty {
                responseView
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96)).combined(with: .offset(y: 6)),
                        removal: .opacity
                    ))
            }

            // Status indicator (listening, thinking, etc.)
            if viewModel.status.isActive {
                statusView
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92)),
                        removal: .opacity
                    ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: viewModel.streamingText) { _, newValue in
            if !newValue.isEmpty && newValue != previousStreamingText {
                withAnimation(.easeOut(duration: 0.25)) { showResponse = true }
                previousStreamingText = newValue
                scheduleAutoDismiss(for: newValue)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.status)
    }

    // MARK: - Response View

    private var responseView: some View {
        Text(viewModel.streamingText)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.black.opacity(0.45))
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .opacity(0.3)
                    )
            )
            .shadow(color: .black.opacity(0.2), radius: 20, y: 4)
            .frame(maxWidth: 440)
    }

    // MARK: - Status View

    private var statusView: some View {
        HStack(spacing: 6) {
            // Animated dots for active states
            if viewModel.status == .listening {
                pulsingDot
            } else if viewModel.status != .idle {
                thinkingDots
            }

            Text(viewModel.status.displayText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(.black.opacity(0.35))
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .opacity(0.2)
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 2)
    }

    // MARK: - Animated Elements

    private var pulsingDot: some View {
        Circle()
            .fill(.red.opacity(0.8))
            .frame(width: 6, height: 6)
            .scaleEffect(1.0)
            .modifier(PulseModifier())
    }

    private var thinkingDots: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.white.opacity(0.6))
                    .frame(width: 4, height: 4)
                    .modifier(BounceDotModifier(delay: Double(i) * 0.15))
            }
        }
    }

    // MARK: - Auto-dismiss

    private func scheduleAutoDismiss(for text: String) {
        let wordCount = text.split(separator: " ").count
        // 1.5s base + 0.1s per word, capped at 5s
        let duration = min(5.0, 1.5 + Double(wordCount) * 0.1)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            // Only dismiss if the text hasn't changed (new response would reschedule)
            if viewModel.streamingText == text || viewModel.status == .idle {
                withAnimation(.easeOut(duration: 0.4)) { showResponse = false }
            }
        }
    }
}

// MARK: - Animation Modifiers

private struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

private struct BounceDotModifier: ViewModifier {
    let delay: Double
    @State private var isBouncing = false

    func body(content: Content) -> some View {
        content
            .offset(y: isBouncing ? -3 : 0)
            .animation(
                .easeInOut(duration: 0.4)
                .repeatForever(autoreverses: true)
                .delay(delay),
                value: isBouncing
            )
            .onAppear { isBouncing = true }
    }
}
