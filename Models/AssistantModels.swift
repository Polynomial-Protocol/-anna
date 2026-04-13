import Foundation

enum CaptureMode: String, Sendable {
    case assistantCommand
    case dictation
    case rewriteDictation   // Toggle-based: transcribe → rewrite → insert
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
    case playOnSpotify(query: String)
    case playOnAppleMusic(query: String)
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

struct ConversationTurn: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    let role: ConversationRole
    let content: String
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp
    }

    init(role: ConversationRole, content: String, timestamp: Date) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.role = try c.decode(ConversationRole.self, forKey: .role)
        self.content = try c.decode(String.self, forKey: .content)
        self.timestamp = try c.decode(Date.self, forKey: .timestamp)
    }
}

enum ConversationRole: String, Codable, Sendable {
    case user
    case assistant
}

// MARK: - Chat Sessions

struct ChatSession: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    var turns: [ConversationTurn]
    var createdAt: Date
    var updatedAt: Date

    var previewText: String {
        turns.last?.content.prefix(80).description ?? "New conversation"
    }

    init(title: String = "New Chat") {
        self.id = UUID()
        self.title = title
        self.turns = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Pointer Coordinate

enum PointerAction: Sendable {
    case point
    case click
}

struct PointerCoordinate: Sendable {
    let x: CGFloat
    let y: CGFloat
    let label: String?
    let action: PointerAction
    /// The screenshot dimensions that the x,y coordinates are relative to.
    let screenshotWidth: CGFloat
    let screenshotHeight: CGFloat
    /// The display dimensions in AppKit points — used for coordinate scaling.
    let displayWidthPoints: CGFloat
    let displayHeightPoints: CGFloat
}

// MARK: - Settings Persistence

struct AppSettings: Codable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = Self.currentSchemaVersion
    var requiresConfirmationForPurchases: Bool = true
    var autoReuseSuccessfulRoutes: Bool = true
    var preferredBrowserBundleID: String = "com.apple.Safari"
    var ttsEnabled: Bool = true
    var ttsRate: Float = 0.46
    var ttsVoiceIdentifier: String = "com.apple.voice.compact.en-US.Samantha"
    var lastSelectedTab: String = "Anna"
    var knowledgeBaseEnabled: Bool = true
    var clipboardCaptureEnabled: Bool = true
    var aiProvider: String = AIProvider.anthropic.rawValue
    var activeTourGuideID: String = ""

    static let defaultValue = AppSettings()

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: "anna_settings"),
              var settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .defaultValue
        }
        if settings.schemaVersion < currentSchemaVersion {
            settings = migrate(settings)
            settings.save()
        }
        return settings
    }

    private static func migrate(_ old: AppSettings) -> AppSettings {
        var s = old
        s.schemaVersion = currentSchemaVersion
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "anna_settings")
        }
    }
}
