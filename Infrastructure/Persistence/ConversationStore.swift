import Foundation

actor ConversationStore {
    private var sessions: [ChatSession] = []
    private var activeSessionID: UUID?
    private let maxTurnsPerSession = 100
    private let directory: URL

    init(directory: URL = PersistenceManager.conversationDirectory) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.sessions = Self.loadSessions(from: directory)
        self.activeSessionID = sessions.first?.id
    }

    // MARK: - Session Management

    var activeSessions: [ChatSession] {
        sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    var activeSession: ChatSession? {
        sessions.first { $0.id == activeSessionID }
    }

    @discardableResult
    func newSession(title: String = "New Chat") -> ChatSession {
        let session = ChatSession(title: title)
        sessions.append(session)
        activeSessionID = session.id
        saveSession(session)
        return session
    }

    func selectSession(_ id: UUID) {
        activeSessionID = id
    }

    func deleteSession(_ id: UUID) {
        let fileName = "\(id.uuidString).json"
        let fileURL = directory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
        sessions.removeAll { $0.id == id }
        if activeSessionID == id {
            activeSessionID = sessions.sorted(by: { $0.updatedAt > $1.updatedAt }).first?.id
        }
    }

    // MARK: - Turn Management

    func append(_ turn: ConversationTurn) {
        if activeSessionID == nil {
            newSession()
        }
        guard let idx = sessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        sessions[idx].turns.append(turn)
        if sessions[idx].turns.count > maxTurnsPerSession {
            sessions[idx].turns = Array(sessions[idx].turns.suffix(maxTurnsPerSession))
        }
        sessions[idx].updatedAt = Date()

        // Auto-title from first user message
        if sessions[idx].title == "New Chat",
           let firstUser = sessions[idx].turns.first(where: { $0.role == .user }) {
            sessions[idx].title = String(firstUser.content.prefix(40))
        }

        saveSession(sessions[idx])
    }

    func recentTurns(_ count: Int) -> [ConversationTurn] {
        guard let session = activeSession else { return [] }
        return Array(session.turns.suffix(count))
    }

    func allTurns() -> [ConversationTurn] {
        activeSession?.turns ?? []
    }

    func clear() {
        guard let idx = sessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        sessions[idx].turns.removeAll()
        sessions[idx].updatedAt = Date()
        saveSession(sessions[idx])
    }

    // MARK: - Search

    func searchSessions(query: String) -> [ChatSession] {
        let q = query.lowercased()
        return sessions.filter {
            $0.title.lowercased().contains(q) ||
            $0.turns.contains(where: { $0.content.lowercased().contains(q) })
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Persistence

    private func saveSession(_ session: ChatSession) {
        let fileURL = directory.appendingPathComponent("\(session.id.uuidString).json")
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func loadSessions(from directory: URL) -> [ChatSession] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" }) else { return [] }

        return files.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let session = try? JSONDecoder().decode(ChatSession.self, from: data) else { return nil }
            return session
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
}
