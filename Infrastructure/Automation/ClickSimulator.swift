import AppKit
import CoreGraphics

@MainActor
enum ClickSimulator {

    /// Simulates a left mouse click at AppKit screen coordinates (bottom-left origin).
    /// Converts to Quartz coordinates (top-left origin) before posting the event.
    static func click(at appKitPoint: CGPoint) {
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 1080
        let quartzPoint = CGPoint(x: appKitPoint.x, y: primaryScreenHeight - appKitPoint.y)

        let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: quartzPoint, mouseButton: .left)
        let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: quartzPoint, mouseButton: .left)

        mouseDown?.post(tap: .cghidEventTap)
        usleep(50_000) // 50ms between down and up for reliability
        mouseUp?.post(tap: .cghidEventTap)
    }
}
