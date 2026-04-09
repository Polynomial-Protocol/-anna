import SwiftUI
import AppKit

// MARK: - Floating NSPanel

final class TextBarPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 58),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
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
}

// MARK: - Controller

@MainActor
final class TextBarController: ObservableObject {
    @Published var isVisible = false
    private var panel: TextBarPanel?

    func toggle(viewModel: AssistantViewModel) {
        if isVisible {
            hide()
        } else {
            show(viewModel: viewModel)
        }
    }

    func show(viewModel: AssistantViewModel) {
        guard panel == nil else {
            panel?.orderFront(nil)
            panel?.makeKey()
            isVisible = true
            return
        }

        let newPanel = TextBarPanel()

        let hostView = NSHostingView(
            rootView: TextBarContent(viewModel: viewModel, onDismiss: { [weak self] in
                self?.hide()
            })
        )
        newPanel.contentView = hostView

        // Center on current screen, slightly above middle (multi-monitor aware)
        let screen = NSScreen.main ?? NSScreen.screens.first
        if let screenFrame = screen?.visibleFrame {
            let x = screenFrame.midX - 280
            let y = screenFrame.midY + screenFrame.height * 0.18
            newPanel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Animate in
        newPanel.alphaValue = 0
        newPanel.orderFront(nil)
        newPanel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            newPanel.animator().alphaValue = 1.0
        }

        panel = newPanel
        isVisible = true
    }

    func hide() {
        guard let existingPanel = panel else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
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

// MARK: - TextBar Content View

struct TextBarContent: View {
    @ObservedObject var viewModel: AssistantViewModel
    @State private var inputText: String = ""
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.status == .thinking ? "brain" : "message")
                .font(.system(size: 14))
                .foregroundStyle(viewModel.status.color)

            TextField("Hey Anna...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.85))
                .onSubmit {
                    let text = inputText.trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty else { return }
                    viewModel.sendText(text)
                    inputText = ""
                    onDismiss()
                }

            if viewModel.status == .thinking {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 520)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
    }
}
