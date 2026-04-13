import Foundation
import NaturalLanguage
import SQLite3

actor KnowledgeStore {
    private var db: OpaquePointer?
    private let dbPath: String
    private let embeddingService = EmbeddingService()
    private var embeddingCache: [(id: Int64, embedding: [Float])] = []

    init() {
        let dir = PersistenceManager.appSupportURL.appendingPathComponent("knowledge")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.dbPath = dir.appendingPathComponent("knowledge.db").path
        openDatabase()
        createTables()
        Task { await loadEmbeddingCache() }
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
        let entryID = sqlite3_last_insert_rowid(db)

        // Generate and store embedding in background
        Task {
            await generateAndStoreEmbedding(entryID: entryID, text: "\(autoTitle) \(content)")
        }

        return entryID
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

    /// Find entries relevant to a query using hybrid search (vector + FTS5).
    func findRelevant(query: String, limit: Int = 3) -> [KnowledgeEntry] {
        // Vector search (semantic similarity)
        let vectorResults = vectorSearch(query: query, limit: limit * 2)

        // FTS5 keyword search
        let ftsResults = search(query: query, limit: limit * 2)

        // Merge by combined score: 70% vector, 30% keyword
        var scores: [Int64: Double] = [:]
        for (i, entry) in vectorResults.enumerated() {
            scores[entry.id, default: 0] += (1.0 - Double(i) / Double(max(vectorResults.count, 1))) * 0.7
        }
        for (i, entry) in ftsResults.enumerated() {
            scores[entry.id, default: 0] += (1.0 - Double(i) / Double(max(ftsResults.count, 1))) * 0.3
        }

        // Collect all unique entries
        var entryMap: [Int64: KnowledgeEntry] = [:]
        for e in vectorResults + ftsResults { entryMap[e.id] = e }

        let sorted = scores.sorted { $0.value > $1.value }.prefix(limit)
        return sorted.compactMap { entryMap[$0.key] }
    }

    // MARK: - Vector Search

    private func vectorSearch(query: String, limit: Int = 10) -> [KnowledgeEntry] {
        guard !embeddingCache.isEmpty else { return [] }
        guard let queryVec = embeddingService_syncEmbed(query) else { return [] }
        var scored = embeddingCache.map { (id: $0.id, score: cosineSim(queryVec, $0.embedding)) }
        scored.sort { $0.score > $1.score }
        let topIDs = scored.prefix(limit).map { $0.id }

        guard !topIDs.isEmpty else { return [] }
        let placeholders = topIDs.map { _ in "?" }.joined(separator: ",")
        let sql = "SELECT id, title, content, source_type, created_at FROM entries WHERE id IN (\(placeholders))"
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (i, id) in topIDs.enumerated() {
            sqlite3_bind_int64(stmt, Int32(i + 1), id)
        }
        return readEntries(from: stmt)
    }

    private func cosineSim(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, magA: Float = 0, magB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]; magA += a[i] * a[i]; magB += b[i] * b[i]
        }
        let d = sqrt(magA) * sqrt(magB)
        return d > 0 ? dot / d : 0
    }

    /// Synchronous embedding within the actor (NLEmbedding is thread-safe)
    private nonisolated func embeddingService_syncEmbed(_ text: String) -> [Float]? {
        guard let model = NLEmbedding.sentenceEmbedding(for: .english) else { return nil }
        return model.vector(for: text)?.map { Float($0) }
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
                created_at REAL NOT NULL,
                memory_type TEXT NOT NULL DEFAULT 'episodic',
                access_count INTEGER NOT NULL DEFAULT 0
            )
        """)

        // Add columns if they don't exist (migration for existing databases)
        execute("ALTER TABLE entries ADD COLUMN memory_type TEXT NOT NULL DEFAULT 'episodic'")
        execute("ALTER TABLE entries ADD COLUMN access_count INTEGER NOT NULL DEFAULT 0")

        // Embeddings table
        execute("""
            CREATE TABLE IF NOT EXISTS embeddings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                entry_id INTEGER NOT NULL UNIQUE,
                embedding BLOB NOT NULL,
                created_at REAL NOT NULL,
                FOREIGN KEY (entry_id) REFERENCES entries(id) ON DELETE CASCADE
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

    // MARK: - Embedding Storage

    private func generateAndStoreEmbedding(entryID: Int64, text: String) async {
        guard let vector = await embeddingService.embed(text) else { return }
        let data = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        let now = Date().timeIntervalSince1970

        let sql = "INSERT OR REPLACE INTO embeddings (entry_id, embedding, created_at) VALUES (?, ?, ?)"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, entryID)
        data.withUnsafeBytes { ptr in
            sqlite3_bind_blob(stmt, 2, ptr.baseAddress, Int32(data.count), nil)
        }
        sqlite3_bind_double(stmt, 3, now)
        sqlite3_step(stmt)

        // Update in-memory cache
        embeddingCache.append((id: entryID, embedding: vector))
    }

    private func loadEmbeddingCache() {
        let sql = "SELECT entry_id, embedding FROM embeddings"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }

        var cache: [(id: Int64, embedding: [Float])] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let entryID = sqlite3_column_int64(stmt, 0)
            guard let blobPtr = sqlite3_column_blob(stmt, 1) else { continue }
            let blobSize = Int(sqlite3_column_bytes(stmt, 1))
            let floatCount = blobSize / MemoryLayout<Float>.size
            let buffer = UnsafeBufferPointer(start: blobPtr.assumingMemoryBound(to: Float.self), count: floatCount)
            cache.append((id: entryID, embedding: Array(buffer)))
        }
        embeddingCache = cache
    }

    /// Batch-embed existing entries that don't have embeddings yet.
    func backfillEmbeddings(batchSize: Int = 50) async {
        let sql = """
            SELECT e.id, e.title, e.content FROM entries e
            LEFT JOIN embeddings em ON em.entry_id = e.id
            WHERE em.id IS NULL
            LIMIT ?
        """
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(batchSize))

        var pending: [(id: Int64, text: String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            guard let titlePtr = sqlite3_column_text(stmt, 1),
                  let contentPtr = sqlite3_column_text(stmt, 2) else { continue }
            let text = "\(String(cString: titlePtr)) \(String(cString: contentPtr))"
            pending.append((id: id, text: text))
        }

        for item in pending {
            await generateAndStoreEmbedding(entryID: item.id, text: item.text)
        }
    }
}
