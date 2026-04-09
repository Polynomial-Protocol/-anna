import Foundation

actor ConversationStore {
    private var turns: [ConversationTurn] = []
    private let maxTurns = 100
    private let fileURL: URL

    init(fileURL: URL = PersistenceManager.conversationHistoryURL) {
        self.fileURL = fileURL
        self.turns = Self.loadFromDisk(url: fileURL)
    }

    func append(_ turn: ConversationTurn) {
        turns.append(turn)
        if turns.count > maxTurns {
            turns = Array(turns.suffix(maxTurns))
        }
        saveToDisk()
    }

    func recentTurns(_ count: Int) -> [ConversationTurn] {
        Array(turns.suffix(count))
    }

    func allTurns() -> [ConversationTurn] {
        turns
    }

    func clear() {
        turns.removeAll()
        saveToDisk()
    }

    private func saveToDisk() {
        guard let data = try? JSONEncoder().encode(turns) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func loadFromDisk(url: URL) -> [ConversationTurn] {
        guard let data = try? Data(contentsOf: url),
              let turns = try? JSONDecoder().decode([ConversationTurn].self, from: data) else {
            return []
        }
        return turns
    }
}
