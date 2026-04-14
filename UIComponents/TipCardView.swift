import SwiftUI
import AppKit

/// Minimal clickable tip card shown at the top-right of the screen.
/// Closes the learning loop: Follow / Not now / Never-for-this-app all
/// call back into `AssistantEngine` + `AppSettings` so the wiki's
/// per-app confidence grows or decays.

@MainActor
final class TipCardPanel: NSPanel {
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
        hasShadow = true
        // Tip card MUST be interactive — buttons need to work.
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { false }   // never steal focus
    override var canBecomeMain: Bool { false }
}

@MainActor
final class TipCardController: ObservableObject {
    /// Observed by `AnnaApp` so the status bar can show a small pulsing
    /// dot badge while a tip is waiting for the user.
    @Published private(set) var isVisible: Bool = false

    private var panel: TipCardPanel?
    private let width: CGFloat = 320
    private let height: CGFloat = 148
    private var currentBundleID: String = ""
    private var currentContext: String = ""

    private let engine: AssistantEngine
    private let settingsProvider: () -> AppSettings
    private let settingsUpdater: (AppSettings) -> Void

    init(engine: AssistantEngine,
         settingsProvider: @escaping () -> AppSettings,
         settingsUpdater: @escaping (AppSettings) -> Void) {
        self.engine = engine
        self.settingsProvider = settingsProvider
        self.settingsUpdater = settingsUpdater
    }

    func show(tip: String, bundleID: String, appName: String) {
        currentBundleID = bundleID
        currentContext = tip

        let view = TipCardView(
            tip: tip,
            appName: appName,
            onFollow:   { [weak self] in self?.handleFollow() },
            onDismiss:  { [weak self] in self?.handleDismiss() },
            onSuppress: { [weak self] in self?.handleSuppress() }
        )

        isVisible = true
        if panel == nil {
            let frame = NSRect(x: 0, y: 0, width: width, height: height)
            let p = TipCardPanel(contentRect: frame)
            p.contentView = NSHostingView(rootView: view.frame(width: width, height: height))
            if let sf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
                p.setFrameOrigin(NSPoint(x: sf.maxX - width - 16, y: sf.maxY - height - 8))
            }
            p.alphaValue = 0
            p.orderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                p.animator().alphaValue = 1.0
            }
            panel = p
        } else {
            panel?.contentView = NSHostingView(rootView: view.frame(width: width, height: height))
            panel?.orderFront(nil)
        }
    }

    func hide() {
        guard let p = panel else { isVisible = false; return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            p.orderOut(nil)
            self?.panel = nil
            self?.isVisible = false
        })
    }

    private func handleFollow() {
        let engine = engine
        Task { await engine.recordTipFollowed() }
        hide()
    }

    private func handleDismiss() {
        let engine = engine
        let ctx = currentContext
        Task { await engine.recordTipDismissed(context: ctx) }
        hide()
    }

    private func handleSuppress() {
        var s = settingsProvider()
        if !s.suppressedOnboardingBundleIDs.contains(currentBundleID) {
            s.suppressedOnboardingBundleIDs.append(currentBundleID)
            settingsUpdater(s)
        }
        let engine = engine
        let ctx = currentContext
        Task { await engine.recordTipDismissed(context: "[suppressed] \(ctx)") }
        hide()
    }
}

struct TipCardView: View {
    let tip: String
    let appName: String
    let onFollow: () -> Void
    let onDismiss: () -> Void
    let onSuppress: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                Text("Anna · \(appName)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            Text(tip)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
            HStack(spacing: 8) {
                Button("Got it", action: onFollow)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Not now", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
                Button("Never for this app", action: onSuppress)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
}
