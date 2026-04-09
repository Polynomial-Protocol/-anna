import AppKit
import ApplicationServices
import Foundation

final class ActiveTextInsertionService: TextInsertionService {
    private let permissionService: PermissionService

    init(permissionService: PermissionService) {
        self.permissionService = permissionService
    }

    func insertText(_ text: String) async throws {
        // Put text on clipboard
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Wait for modifier keys (Option, Command) to be fully released
        // so they don't interfere with the synthetic Cmd+V
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
        await waitForModifierKeysReleased(timeout: 1.0)
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms after release

        // Try CGEvent-based Cmd+V first (requires Accessibility permission)
        if AXIsProcessTrusted() {
            // Use a private event source so our Cmd+V isn't combined with
            // any physical keys the user might still be touching
            if let source = CGEventSource(stateID: .privateState),
               let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {
                keyDown.flags = .maskCommand
                keyUp.flags = .maskCommand
                keyDown.post(tap: .cghidEventTap)
                try? await Task.sleep(nanoseconds: 30_000_000) // 30ms between down/up
                keyUp.post(tap: .cghidEventTap)
                return
            }
        }

        // Fallback: AppleScript keystroke (uses Automation permission)
        let script = NSAppleScript(source: """
            tell application "System Events"
                keystroke "v" using command down
            end tell
        """)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)

        if error != nil {
            // Last resort: try to restore clipboard and report failure
            if let old = oldContents {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
            throw AnnaError.permissionMissing(.accessibility)
        }
    }

    /// Waits until all modifier keys are released before proceeding
    private func waitForModifierKeysReleased(timeout: TimeInterval) async {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if let source = CGEventSource(stateID: .combinedSessionState) {
                let flags = CGEventSource.flagsState(.combinedSessionState)
                let modifiers: CGEventFlags = [.maskAlternate, .maskCommand, .maskControl, .maskShift]
                if flags.intersection(modifiers).isEmpty {
                    return // All modifier keys released
                }
            } else {
                return // Can't check, proceed anyway
            }
            try? await Task.sleep(nanoseconds: 50_000_000) // Check every 50ms
        }
    }
}
