import AppKit
import ApplicationServices
import Foundation

final class ActiveTextInsertionService: TextInsertionService {
    private let permissionService: PermissionService

    init(permissionService: PermissionService) {
        self.permissionService = permissionService
    }

    func insertText(_ text: String) async throws {
        let accessibilityStatus = permissionService.currentStatuses().first { $0.kind == .accessibility }
        guard accessibilityStatus?.state == .granted else {
            throw AnnaError.permissionMissing(.accessibility)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            throw AnnaError.insertionFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
