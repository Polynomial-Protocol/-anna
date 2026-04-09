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

        // Small delay to ensure clipboard is ready
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Try CGEvent-based Cmd+V first (requires Accessibility permission)
        if AXIsProcessTrusted() {
            if let source = CGEventSource(stateID: .hidSystemState),
               let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {
                keyDown.flags = .maskCommand
                keyUp.flags = .maskCommand
                keyDown.post(tap: .cghidEventTap)
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
}
