import AppKit
import Foundation

@MainActor
final class ModifierKeyMonitor: ObservableObject {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    // Right-side modifier key codes only
    private let rightCommandKeyCode: UInt16 = 54
    private let rightOptionKeyCode: UInt16 = 61

    private var isRightCommandDown = false
    private var isRightOptionDown = false

    var onCommandPressed: (() -> Void)?
    var onCommandReleased: (() -> Void)?
    var onOptionPressed: (() -> Void)?
    var onOptionReleased: (() -> Void)?

    func start() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.handleModifierEvent(event)
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierEvent(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handleModifierEvent(_ event: NSEvent) {
        switch event.keyCode {
        case rightCommandKeyCode:
            let rightCommandPressed = event.modifierFlags.contains(.command)
            if rightCommandPressed && !isRightCommandDown {
                isRightCommandDown = true
                onCommandPressed?()
            } else if !rightCommandPressed && isRightCommandDown {
                isRightCommandDown = false
                onCommandReleased?()
            }

        case rightOptionKeyCode:
            let rightOptionPressed = event.modifierFlags.contains(.option)
            if rightOptionPressed && !isRightOptionDown {
                isRightOptionDown = true
                onOptionPressed?()
            } else if !rightOptionPressed && isRightOptionDown {
                isRightOptionDown = false
                onOptionReleased?()
            }

        default:
            break
        }
    }
}
