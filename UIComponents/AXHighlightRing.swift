import Foundation
import AppKit
import ApplicationServices

/// A borderless, click-through overlay NSPanel that draws a subtle ring
/// around a specific on-screen rectangle. Used by the walkthrough stepper
/// to point at a UI element by AX position + size.
///
/// AX coordinates use a top-left origin on the primary display; AppKit
/// window frames use a bottom-left origin. The converter `flipAXRect`
/// handles that so callers can pass raw AX rects directly.
@MainActor
final class AXHighlightRingController {

    private var panel: NSPanel?

    /// Draws (or updates) the highlight ring around the given AX rect.
    /// Pass nil to clear.
    func show(axRect: CGRect?, pulse: Bool = true) {
        guard let rect = axRect, rect.width > 4, rect.height > 4 else { hide(); return }

        let screenRect = flipAXRect(rect)
        if panel == nil {
            let p = RingPanel(contentRect: screenRect)
            p.contentView = RingNSView(frame: NSRect(origin: .zero, size: screenRect.size),
                                       pulse: pulse)
            p.alphaValue = 0
            p.orderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                p.animator().alphaValue = 1.0
            }
            panel = p
        } else {
            panel?.setFrame(screenRect, display: true, animate: false)
            if let view = panel?.contentView as? RingNSView {
                view.frame = NSRect(origin: .zero, size: screenRect.size)
                view.pulse = pulse
                view.needsDisplay = true
            }
        }
    }

    func hide() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            p.orderOut(nil)
            self?.panel = nil
        })
    }

    /// AX screen rect → AppKit screen rect on the primary display.
    /// AX y-origin is the top of the main display; AppKit's is the bottom.
    private func flipAXRect(_ r: CGRect) -> NSRect {
        guard let screen = NSScreen.screens.first else { return r }
        let pad: CGFloat = 4
        let flipped = NSRect(
            x: r.origin.x - pad,
            y: screen.frame.height - r.origin.y - r.height - pad,
            width: r.width + pad * 2,
            height: r.height + pad * 2
        )
        return flipped
    }
}

private final class RingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class RingNSView: NSView {
    var pulse: Bool
    private var pulseTimer: Timer?
    private var phase: CGFloat = 0

    init(frame: NSRect, pulse: Bool) {
        self.pulse = pulse
        super.init(frame: frame)
        if pulse {
            pulseTimer = Timer.scheduledTimer(withTimeInterval: 1 / 30.0, repeats: true) { [weak self] _ in
                self?.phase += 0.03
                self?.needsDisplay = true
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { pulseTimer?.invalidate() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let wave = (sin(phase * 2) + 1) / 2  // 0…1
        let lineWidth: CGFloat = 2.5
        let corner: CGFloat = 6
        let alpha: CGFloat = 0.55 + wave * 0.35

        let rect = bounds.insetBy(dx: lineWidth, dy: lineWidth)
        let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
        path.lineWidth = lineWidth
        NSColor.systemBlue.withAlphaComponent(alpha).setStroke()
        path.stroke()
    }
}
