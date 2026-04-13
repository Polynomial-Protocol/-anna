import Foundation

struct KnowledgeEntry: Identifiable, Sendable {
    let id: Int64
    let title: String
    let content: String
    let source: EntrySource
    let createdAt: Date
    var memoryType: MemoryType = .episodic
    var accessCount: Int = 0
}

// MARK: - Memory Types

enum MemoryType: String, Codable, Sendable, CaseIterable {
    case episodic       // Raw conversations, events — decays after 30 days
    case semantic       // Distilled facts, patterns — decays after 18 months
    case procedural     // How-to knowledge, routines — never decays
    case contextual     // Current session state — end of session
    case permanent      // User-pinned memories — never decays

    var displayName: String {
        switch self {
        case .episodic: return "Episodic"
        case .semantic: return "Fact"
        case .procedural: return "How-to"
        case .contextual: return "Session"
        case .permanent: return "Pinned"
        }
    }

    var decayDays: Int? {
        switch self {
        case .episodic: return 30
        case .semantic: return 540  // 18 months
        case .procedural: return nil
        case .contextual: return 1
        case .permanent: return nil
        }
    }
}

// MARK: - Data Retention

enum RetentionPolicy: String, Codable, Sendable {
    case permanent
    case sixMonths = "6_months"
    case oneYear = "1_year"
    case untilExpired = "until_expired"
    case userOnly = "user_only"
}

enum EntrySource: String, Codable, Sendable, CaseIterable {
    case clipboard
    case conversation
    case note
    case url
    case screenshot

    var icon: String {
        switch self {
        case .clipboard: return "doc.on.clipboard"
        case .conversation: return "bubble.left.and.bubble.right"
        case .note: return "note.text"
        case .url: return "link"
        case .screenshot: return "camera.viewfinder"
        }
    }

    var displayName: String {
        switch self {
        case .clipboard: return "Clipboard"
        case .conversation: return "Conversation"
        case .note: return "Note"
        case .url: return "URL"
        case .screenshot: return "Screenshot"
        }
    }
}
