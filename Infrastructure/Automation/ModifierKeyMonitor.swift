import AppKit
import CoreGraphics
import Foundation

@MainActor
final class ModifierKeyMonitor: ObservableObject {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalNSMonitor: Any?
    private var localNSMonitor: Any?

    private static let rightCommandKeyCode: UInt16 = 54
    private static let rightOptionKeyCode: UInt16 = 61

    private var isRightCommandDown = false
    private var isRightOptionDown = false
    private var tapHealthTimer: Timer?

    var onCommandPressed: (() -> Void)?
    var onCommandReleased: (() -> Void)?
    var onOptionPressed: (() -> Void)?
    var onOptionReleased: (() -> Void)?

    func start() {
        // Use BOTH CGEventTap and NSEvent monitors for maximum reliability.
        // CGEventTap catches events globally even in other apps.
        // NSEvent monitors serve as fallback when CGEventTap fails.
        createEventTap()
        startNSEventMonitors()

        // Check tap health every 3 seconds — recreate if disabled
        tapHealthTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkTapHealth()
            }
        }
    }

    func stop() {
        tapHealthTimer?.invalidate()
        tapHealthTimer = nil
        destroyEventTap()

        if let globalNSMonitor {
            NSEvent.removeMonitor(globalNSMonitor)
        }
        if let localNSMonitor {
            NSEvent.removeMonitor(localNSMonitor)
        }
        globalNSMonitor = nil
        localNSMonitor = nil
    }

    // MARK: - CGEventTap

    private func createEventTap() {
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.flagsChanged.rawValue),
            callback: { _, _, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<ModifierKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags
                DispatchQueue.main.async {
                    monitor.handleCGEvent(keyCode: keyCode, flags: flags)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func destroyEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func checkTapHealth() {
        if let tap = eventTap {
            if !CGEvent.tapIsEnabled(tap: tap) {
                // Try to re-enable
                CGEvent.tapEnable(tap: tap, enable: true)
                // If still disabled, recreate the tap entirely
                if !CGEvent.tapIsEnabled(tap: tap) {
                    destroyEventTap()
                    createEventTap()
                }
            }
        } else {
            // No tap exists — try to create one (maybe accessibility was just granted)
            createEventTap()
        }
    }

    // MARK: - NSEvent Monitors (always active as backup)

    private func startNSEventMonitors() {
        globalNSMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            DispatchQueue.main.async {
                self.handleNSEvent(keyCode: keyCode, flags: flags)
            }
        }

        localNSMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return event }
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            DispatchQueue.main.async {
                self.handleNSEvent(keyCode: keyCode, flags: flags)
            }
            return event
        }
    }

    // MARK: - Event Handling (separate handlers to avoid duplicates)

    private func handleCGEvent(keyCode: UInt16, flags: CGEventFlags) {
        switch keyCode {
        case Self.rightCommandKeyCode:
            let pressed = flags.contains(.maskCommand)
            if pressed && !isRightCommandDown {
                isRightCommandDown = true
                onCommandPressed?()
            } else if !pressed && isRightCommandDown {
                isRightCommandDown = false
                onCommandReleased?()
            }

        case Self.rightOptionKeyCode:
            let pressed = flags.contains(.maskAlternate)
            if pressed && !isRightOptionDown {
                isRightOptionDown = true
                onOptionPressed?()
            } else if !pressed && isRightOptionDown {
                isRightOptionDown = false
                onOptionReleased?()
            }

        default:
            break
        }
    }

    private func handleNSEvent(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        // NSEvent handler — the state flags (isRightCommandDown etc.) prevent
        // duplicate firings when both CGEventTap and NSEvent detect the same event.
        switch keyCode {
        case Self.rightCommandKeyCode:
            let pressed = flags.contains(.command)
            if pressed && !isRightCommandDown {
                isRightCommandDown = true
                onCommandPressed?()
            } else if !pressed && isRightCommandDown {
                isRightCommandDown = false
                onCommandReleased?()
            }

        case Self.rightOptionKeyCode:
            let pressed = flags.contains(.option)
            if pressed && !isRightOptionDown {
                isRightOptionDown = true
                onOptionPressed?()
            } else if !pressed && isRightOptionDown {
                isRightOptionDown = false
                onOptionReleased?()
            }

        default:
            break
        }
    }
}
