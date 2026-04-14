import SwiftUI
import AppKit

/// Minimal five-step stepper surface used for on-demand walkthroughs.
/// Fed by `TutorialEngine.generateWalkthrough(task:appName:)` → `[WalkthroughStep]`.
///
/// Additive: it's its own floating NSPanel, it doesn't touch the main
/// window or the tip card. Opens via `WalkthroughController.start(...)`.

@MainActor
final class WalkthroughPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true   // user can reposition
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = false
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class WalkthroughController: ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var steps: [TutorialEngine.WalkthroughStep] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var isGenerating: Bool = false
    @Published private(set) var appName: String = ""

    private var panel: WalkthroughPanel?
    private let width: CGFloat = 360
    private let height: CGFloat = 220

    private let tutorialEngine: TutorialEngine
    private let engine: AssistantEngine
    let ringController = AXHighlightRingController()

    init(tutorialEngine: TutorialEngine, engine: AssistantEngine) {
        self.tutorialEngine = tutorialEngine
        self.engine = engine
    }

    /// Entry point: generate a walkthrough for the user's request, then
    /// show the stepper. No-op if the model returns zero steps.
    func start(task: String, appName: String) {
        self.appName = appName
        isGenerating = true
        presentPanel()   // show immediately with a "thinking" state
        Task {
            let generated = await tutorialEngine.generateWalkthrough(task: task, appName: appName)
            await MainActor.run {
                self.isGenerating = false
                if generated.isEmpty {
                    self.dismiss()
                } else {
                    self.steps = Array(generated.prefix(8))
                    self.currentIndex = 0
                }
            }
        }
    }

    func next() {
        guard currentIndex < steps.count - 1 else {
            // Last step → record walkthrough completion as a confidence win.
            let engine = engine
            Task { await engine.recordTipFollowed() }
            dismiss()
            return
        }
        currentIndex += 1
    }

    func back() {
        currentIndex = max(0, currentIndex - 1)
    }

    func dismiss() {
        ringController.hide()
        guard let p = panel else { isVisible = false; return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            p.orderOut(nil)
            self?.panel = nil
            self?.isVisible = false
            self?.steps = []
            self?.currentIndex = 0
        })
    }

    private func presentPanel() {
        if panel != nil { panel?.orderFront(nil); return }
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        let p = WalkthroughPanel(contentRect: frame)
        let view = WalkthroughStepperView(controller: self)
        p.contentView = NSHostingView(rootView: view.frame(width: width, height: height))
        if let sf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: sf.maxX - width - 16, y: sf.midY - height / 2))
        }
        p.alphaValue = 0
        p.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            p.animator().alphaValue = 1.0
        }
        panel = p
        isVisible = true
    }
}

struct WalkthroughStepperView: View {
    @ObservedObject var controller: WalkthroughController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider().opacity(0.15)
            if controller.isGenerating && controller.steps.isEmpty {
                loadingView
            } else if controller.steps.isEmpty {
                Text("No steps available.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                stepContent
                Spacer(minLength: 0)
                progressDots
                controls
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.accentColor).frame(width: 6, height: 6)
            Text("Anna · \(controller.appName)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Button(action: controller.dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.6)
            Text("Planning steps…")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
    }

    @ViewBuilder
    private var stepContent: some View {
        let step = controller.steps[controller.currentIndex]
        VStack(alignment: .leading, spacing: 6) {
            Text(step.title)
                .font(.system(size: 13, weight: .semibold))
            Text(step.body)
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressDots: some View {
        HStack(spacing: 5) {
            ForEach(controller.steps.indices, id: \.self) { i in
                Circle()
                    .fill(i == controller.currentIndex ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 5, height: 5)
            }
        }
    }

    private var controls: some View {
        HStack {
            Button("Back", action: controller.back)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(controller.currentIndex == 0)
            Spacer()
            Text("\(controller.currentIndex + 1) / \(controller.steps.count)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Button(controller.currentIndex == controller.steps.count - 1 ? "Finish" : "Next",
                   action: controller.next)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }
}
