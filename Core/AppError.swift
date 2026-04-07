import Foundation

enum AnnaError: LocalizedError, Equatable, Sendable {
    case permissionMissing(PermissionKind)
    case transcriptionUnavailable
    case automationDenied(String)
    case actionRequiresConfirmation(String)
    case unsupportedAction(String)
    case insertionFailed
    case audioCaptureFailed(String)
    case claudeCLIFailed(String)
    case claudeCLITimeout
    case screenCaptureFailed(String)
    case ttsFailed(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .permissionMissing(let kind):
            return "\(kind.displayName) permission is required."
        case .transcriptionUnavailable:
            return "Parakeet transcription is not configured yet."
        case .automationDenied(let detail):
            return "Automation was blocked. \(detail)"
        case .actionRequiresConfirmation(let detail):
            return detail
        case .unsupportedAction(let detail):
            return detail
        case .insertionFailed:
            return "Anna could not insert text into the active field."
        case .audioCaptureFailed(let detail):
            return "Audio capture failed. \(detail)"
        case .claudeCLIFailed(let detail):
            return "Claude CLI failed: \(detail)"
        case .claudeCLITimeout:
            return "Claude CLI timed out."
        case .screenCaptureFailed(let detail):
            return "Screen capture failed: \(detail)"
        case .ttsFailed(let detail):
            return "Text-to-speech failed: \(detail)"
        case .unknown(let detail):
            return detail
        }
    }
}
