import Foundation

enum PermissionKind: String, CaseIterable, Identifiable, Sendable {
    case microphone
    case accessibility
    case automation
    case screenRecording

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .microphone:
            return "Microphone"
        case .accessibility:
            return "Accessibility"
        case .automation:
            return "Automation"
        case .screenRecording:
            return "Screen Recording"
        }
    }

    var reason: String {
        switch self {
        case .microphone:
            return "Needed for hold-to-talk voice capture."
        case .accessibility:
            return "Needed for global shortcuts, text insertion, and UI pointing."
        case .automation:
            return "Needed to control Safari, Music, and other scriptable apps."
        case .screenRecording:
            return "Needed to capture your screen so Anna can see what you're looking at and guide you."
        }
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
}
