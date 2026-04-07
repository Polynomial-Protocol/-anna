import Foundation

enum CaptureMode: String, Sendable {
    case assistantCommand
    case dictation
}

struct CapturedUtterance: Sendable {
    let fileURL: URL
    let duration: TimeInterval
}

struct TranscriptionResult: Sendable {
    let text: String
    let confidence: Double
}

enum SpeechModelKind: String, Sendable {
    case parakeetV2English
}

enum SpeechModelState: String, Sendable {
    case notInstalled
    case downloading
    case ready
    case failed
}

struct SpeechModelStatus: Sendable {
    let kind: SpeechModelKind
    var state: SpeechModelState
    var detail: String
}

enum AssistantIntent: Equatable, Sendable {
    case searchWeb(query: String)
    case researchProduct(query: String)
    case playMedia(query: String)
    case orderProduct(query: String)
    case openApp(name: String)
    case dictateOnly
    case unsupported
}

// MARK: - Two-Tier Execution

enum ExecutionTier: Sendable {
    case direct(DirectAction)
    case agent(String)
}

enum DirectAction: Sendable {
    case mediaControl(command: String)
    case openApp(name: String)
    case systemControl(command: String)
    case playOnYouTube(query: String)
    case searchWeb(query: String)
    case openURL(url: String)
}

enum AutomationOutcome: Sendable {
    case completed(summary: String, openedURL: URL?)
    case needsConfirmation(summary: String)
    case blocked(summary: String)
}

struct AssistantEvent: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let title: String
    let body: String
    let tone: EventTone

    enum EventTone: Sendable {
        case neutral
        case success
        case warning
        case failure
    }
}

// MARK: - Conversation History

struct ConversationTurn: Sendable {
    let role: ConversationRole
    let content: String
    let timestamp: Date
}

enum ConversationRole: String, Sendable {
    case user
    case assistant
}

// MARK: - Pointer Coordinate

struct PointerCoordinate: Sendable {
    let x: CGFloat
    let y: CGFloat
    let label: String?
}

// MARK: - Settings Persistence

struct AppSettings: Codable, Sendable {
    var requiresConfirmationForPurchases: Bool = true
    var autoReuseSuccessfulRoutes: Bool = true
    var preferredBrowserBundleID: String = "com.apple.Safari"
    var ttsEnabled: Bool = true
    var ttsRate: Float = 0.50
    var ttsVoiceIdentifier: String = ""  // empty = auto-select best
    var lastSelectedTab: String = "assistant"

    static let defaultValue = AppSettings()

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: "anna_settings"),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .defaultValue
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "anna_settings")
        }
    }
}
