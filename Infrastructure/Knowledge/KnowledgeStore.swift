import Foundation
import SQLite3

actor KnowledgeStore {
    private var db: OpaquePointer?
    private let dbPath: String

    init() {
        let dir = PersistenceManager.appSupportURL.appendingPathComponent("knowledge")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.dbPath = dir.appendingPathComponent("knowledge.db").path
        openDatabase()
        createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Public API

    @discardableResult
    func addEntry(content: String, source: EntrySource, title: String? = nil) -> Int64? {
        let autoTitle = title ?? generateTitle(from: content)
        let now = Date().timeIntervalSince1970

        let sql = "INSERT INTO entries (title, content, source_type, created_at) VALUES (?, ?, ?, ?)"
        guard let stmt = prepare(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (autoTitle as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (content as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (source.rawValue as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 4, now)

        guard sqlite3_step(stmt) == SQLITE_DONE else { return nil }
        return sqlite3_last_insert_rowid(db)
    }

    func search(query: String, limit: Int = 20) -> [KnowledgeEntry] {
        // Use FTS5 for full-text search
        let sql = """
            SELECT e.id, e.title, e.content, e.source_type, e.created_at
            FROM entries_fts f
            JOIN entries e ON e.rowid = f.rowid
            WHERE entries_fts MATCH ?
            ORDER BY rank
            LIMIT ?
        """
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }

        let ftsQuery = query.split(separator: " ").map { "\($0)*" }.joined(separator: " ")
        sqlite3_bind_text(stmt, 1, (ftsQuery as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        return readEntries(from: stmt)
    }

    func recentEntries(limit: Int = 50) -> [KnowledgeEntry] {
        let sql = "SELECT id, title, content, source_type, created_at FROM entries ORDER BY created_at DESC LIMIT ?"
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))
        return readEntries(from: stmt)
    }

    func deleteEntry(id: Int64) {
        let sql = "DELETE FROM entries WHERE id = ?"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        sqlite3_step(stmt)
    }

    func entryCount() -> Int {
        let sql = "SELECT COUNT(*) FROM entries"
        guard let stmt = prepare(sql) else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    /// Find entries relevant to a query for context injection
    func findRelevant(query: String, limit: Int = 3) -> [KnowledgeEntry] {
        let results = search(query: query, limit: limit)
        if results.isEmpty {
            // Fallback: keyword matching on recent entries
            let keywords = query.lowercased().split(separator: " ").filter { $0.count > 3 }
            if keywords.isEmpty { return [] }
            // Search for any keyword match
            let conditions = keywords.map { "content LIKE '%\($0)%'" }.joined(separator: " OR ")
            let sql = "SELECT id, title, content, source_type, created_at FROM entries WHERE \(conditions) ORDER BY created_at DESC LIMIT ?"
            guard let stmt = prepare(sql) else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            return readEntries(from: stmt)
        }
        return results
    }

    // MARK: - Private

    private func openDatabase() {
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            db = nil
            return
        }
    }

    private func createTables() {
        execute("""
            CREATE TABLE IF NOT EXISTS entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                source_type TEXT NOT NULL DEFAULT 'note',
                created_at REAL NOT NULL
            )
        """)

        // FTS5 virtual table for full-text search
        execute("CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(title, content, content=entries, content_rowid=id)")

        // Triggers to keep FTS in sync
        execute("""
            CREATE TRIGGER IF NOT EXISTS entries_ai AFTER INSERT ON entries BEGIN
                INSERT INTO entries_fts(rowid, title, content) VALUES (new.id, new.title, new.content);
            END
        """)
        execute("""
            CREATE TRIGGER IF NOT EXISTS entries_ad AFTER DELETE ON entries BEGIN
                INSERT INTO entries_fts(entries_fts, rowid, title, content) VALUES ('delete', old.id, old.title, old.content);
            END
        """)
    }

    private func execute(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    private func readEntries(from stmt: OpaquePointer) -> [KnowledgeEntry] {
        var entries: [KnowledgeEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            guard let titlePtr = sqlite3_column_text(stmt, 1),
                  let contentPtr = sqlite3_column_text(stmt, 2),
                  let sourcePtr = sqlite3_column_text(stmt, 3) else { continue }

            let title = String(cString: titlePtr)
            let content = String(cString: contentPtr)
            let sourceRaw = String(cString: sourcePtr)
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))

            entries.append(KnowledgeEntry(
                id: id,
                title: title,
                content: content,
                source: EntrySource(rawValue: sourceRaw) ?? .note,
                createdAt: createdAt
            ))
        }
        return entries
    }

    private func generateTitle(from content: String) -> String {
        let firstLine = content.components(separatedBy: CharacterSet.newlines).first ?? content
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 80 { return trimmed }
        return String(trimmed.prefix(77)) + "..."
    }
}
