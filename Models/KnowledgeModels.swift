import Foundation

struct KnowledgeEntry: Identifiable, Sendable {
    let id: Int64
    let title: String
    let content: String
    let source: EntrySource
    let createdAt: Date
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
