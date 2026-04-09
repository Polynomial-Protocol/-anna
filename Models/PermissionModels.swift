import Foundation

enum PermissionKind: String, CaseIterable, Identifiable, Sendable {
    case microphone
    case accessibility
    case screenRecording
    case automation
    case reminders
    case calendar
    case contacts
    case notifications

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .microphone: return "Microphone"
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        case .automation: return "Automation"
        case .reminders: return "Reminders"
        case .calendar: return "Calendar"
        case .contacts: return "Contacts"
        case .notifications: return "Notifications"
        }
    }

    var reason: String {
        switch self {
        case .microphone:
            return "Listens while you hold a hotkey so Anna can hear your voice commands and dictation."
        case .accessibility:
            return "Lets Anna read what's on screen, insert text into any app, and respond to global hotkeys."
        case .screenRecording:
            return "Lets Anna see your screen so it can point to buttons, menus, and guide you visually."
        case .automation:
            return "Lets Anna control apps like Safari and Music when you ask it to take actions for you."
        case .reminders:
            return "Lets Anna create reminders and alarms when you say things like \"remind me\" or \"set an alarm.\""
        case .calendar:
            return "Lets Anna create and read calendar events when you ask about your schedule or want to add meetings."
        case .contacts:
            return "Lets Anna look up contact information when you ask to call, text, or email someone."
        case .notifications:
            return "Lets Anna send you notifications for reminders, alarms, and completed tasks."
        }
    }

    var icon: String {
        switch self {
        case .microphone: return "mic.fill"
        case .accessibility: return "hand.point.up.left.fill"
        case .screenRecording: return "rectangle.dashed.badge.record"
        case .automation: return "gearshape.2.fill"
        case .reminders: return "alarm.fill"
        case .calendar: return "calendar"
        case .contacts: return "person.crop.circle.fill"
        case .notifications: return "bell.fill"
        }
    }

    var isRequired: Bool {
        switch self {
        case .microphone, .accessibility: return true
        case .screenRecording, .automation, .reminders, .calendar, .contacts, .notifications: return false
        }
    }

    var denialInstructions: String {
        switch self {
        case .microphone:
            return "Open System Settings \u{2192} Privacy & Security \u{2192} Microphone, then turn on Anna."
        case .accessibility:
            return "Open System Settings \u{2192} Privacy & Security \u{2192} Accessibility, then turn on Anna."
        case .screenRecording:
            return "Open System Settings \u{2192} Privacy & Security \u{2192} Screen Recording, then turn on Anna."
        case .automation:
            return "Open System Settings \u{2192} Privacy & Security \u{2192} Automation, then turn on Anna."
        case .reminders:
            return "Open System Settings \u{2192} Privacy & Security \u{2192} Reminders, then turn on Anna."
        case .calendar:
            return "Open System Settings \u{2192} Privacy & Security \u{2192} Calendars, then turn on Anna."
        case .contacts:
            return "Open System Settings \u{2192} Privacy & Security \u{2192} Contacts, then turn on Anna."
        case .notifications:
            return "Open System Settings \u{2192} Notifications \u{2192} Anna, then enable notifications."
        }
    }

    /// The order permissions should be requested during onboarding
    var onboardingOrder: Int {
        switch self {
        case .microphone: return 0
        case .accessibility: return 1
        case .screenRecording: return 2
        case .notifications: return 3
        case .reminders: return 4
        case .calendar: return 5
        case .contacts: return 6
        case .automation: return 7
        }
    }

    static var onboardingSequence: [PermissionKind] {
        allCases.sorted { $0.onboardingOrder < $1.onboardingOrder }
    }
}

enum PermissionState: String, Sendable {
    case notRequested
    case granted
    case denied
    case manualStepRequired
}

struct PermissionStatus: Identifiable, Sendable {
    let kind: PermissionKind
    var state: PermissionState
    var detail: String

    var id: String { kind.id }

    var isGranted: Bool { state == .granted }
    var needsAttention: Bool { state == .denied || state == .manualStepRequired }
}
