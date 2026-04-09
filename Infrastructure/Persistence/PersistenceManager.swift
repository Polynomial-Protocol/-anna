import Foundation

enum PersistenceManager {
    static let appSupportURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("com.damienjacob.anna")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let conversationHistoryURL: URL = {
        appSupportURL.appendingPathComponent("conversation_history.json")
    }()
}
