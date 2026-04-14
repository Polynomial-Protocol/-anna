import Foundation

/// Karpathy-style three-layer knowledge base living on disk as plain markdown.
///
/// Layout under `~/Library/Application Support/Anna/`:
///
/// ```
/// raw/
///   sessions/   ← append-only per-session JSON observations
///   queries/    ← user queries captured as-asked
///   gaps/       ← questions that weren't answered well
/// wiki/
///   index.md    ← master table of contents (compiled)
///   log.md      ← append-only lint/ingest log
///   apps/       ← one markdown file per bundle id
/// schema.md     ← rules for the LLM compiler (never hand-edited)
/// ```
actor WikiKnowledgeBase {

    struct SessionLog: Codable, Sendable {
        let id: UUID
        let appBundleID: String?
        let appName: String?
        let userQuery: String
        let assistantReply: String
        let screenshotWidthPixels: Int?
        let screenshotHeightPixels: Int?
        let followed: Bool?   // nil = unknown
        let timestamp: Date
    }

    enum GapReason: String, Codable, Sendable {
        case dismissed
        case unanswered
        case lowConfidence
    }

    struct KBResult: Sendable {
        let articles: [String]  // wiki markdown chunks
        let confidence: Int     // 0–100
        let gaps: [String]      // recent open gap summaries
        let exists: Bool        // false if we've never compiled a page for this app
    }

    static let shared = WikiKnowledgeBase()

    private let baseURL: URL
    private let encoder: JSONEncoder

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.baseURL = appSupport.appendingPathComponent("Anna", isDirectory: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        self.encoder = e
    }

    // MARK: - Bootstrap

    func bootstrap() {
        let fm = FileManager.default
        for sub in ["raw/sessions", "raw/queries", "raw/gaps", "wiki/apps"] {
            try? fm.createDirectory(at: baseURL.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        let schemaURL = baseURL.appendingPathComponent("schema.md")
        if !fm.fileExists(atPath: schemaURL.path) {
            try? Self.defaultSchema.write(to: schemaURL, atomically: true, encoding: .utf8)
        }
        let logURL = baseURL.appendingPathComponent("wiki/log.md")
        if !fm.fileExists(atPath: logURL.path) {
            try? "# Anna wiki log\n\n".write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Query (used to inject per-app knowledge into the prompt)

    func query(appBundleID: String, appName: String) -> KBResult {
        let page = readAppWiki(bundleID: appBundleID)
        let confidence = readConfidence(bundleID: appBundleID)
        let gaps = recentGaps(bundleID: appBundleID, limit: 5)
        return KBResult(
            articles: page.map { [$0] } ?? [],
            confidence: confidence,
            gaps: gaps,
            exists: page != nil
        )
    }

    // MARK: - Ingest (call at end of a non-internal turn)

    func appendSession(_ log: SessionLog) {
        let dir = baseURL.appendingPathComponent("raw/sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = "\(Int(log.timestamp.timeIntervalSince1970))-\(log.id.uuidString.prefix(8)).json"
        let url = dir.appendingPathComponent(filename)
        if let data = try? encoder.encode(log) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Compile bookkeeping

    /// Returns the count of raw session files for a given bundle id that
    /// were written *after* the last compile timestamp. Callers use this to
    /// decide whether to trigger a recompile (spec threshold: 5).
    func countPendingSessions(bundleID: String) -> Int {
        let sessions = allSessionFiles()
        let since = lastCompileAt(bundleID: bundleID)
        var count = 0
        for url in sessions {
            if let log = loadSession(url: url),
               log.appBundleID == bundleID,
               log.timestamp > since {
                count += 1
            }
        }
        return count
    }

    /// Returns the N most recent raw session logs for a bundle id.
    func recentSessions(bundleID: String, limit: Int) -> [SessionLog] {
        allSessionFiles()
            .compactMap(loadSession)
            .filter { $0.appBundleID == bundleID }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
            .map { $0 }
    }

    func markCompiled(bundleID: String) {
        let url = compileStampURL(bundleID: bundleID)
        try? ISO8601DateFormatter().string(from: Date())
            .write(to: url, atomically: true, encoding: .utf8)
    }

    private func lastCompileAt(bundleID: String) -> Date {
        let url = compileStampURL(bundleID: bundleID)
        guard let s = try? String(contentsOf: url, encoding: .utf8),
              let d = ISO8601DateFormatter().date(from: s.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .distantPast
        }
        return d
    }

    private func compileStampURL(bundleID: String) -> URL {
        baseURL.appendingPathComponent("wiki/apps/\(Self.slug(bundleID)).compiled")
    }

    private func allSessionFiles() -> [URL] {
        let dir = baseURL.appendingPathComponent("raw/sessions", isDirectory: true)
        return (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
    }

    private func loadSession(url: URL) -> SessionLog? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(SessionLog.self, from: data)
    }

    // MARK: - Gaps

    func logGap(query: String, bundleID: String, reason: GapReason) {
        let dir = baseURL.appendingPathComponent("raw/gaps", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let slug = Self.slug(bundleID)
        let line = "- [\(ISO8601DateFormatter().string(from: Date()))] (\(reason.rawValue)) \(query)\n"
        let url = dir.appendingPathComponent("\(slug).md")
        appendLine(line, to: url)
        // Gap logging also drops confidence.
        adjustConfidence(bundleID: bundleID, delta: reason == .dismissed ? -5 : -10)
    }

    private func recentGaps(bundleID: String, limit: Int) -> [String] {
        let url = baseURL.appendingPathComponent("raw/gaps/\(Self.slug(bundleID)).md")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return content.split(separator: "\n").suffix(limit).map(String.init)
    }

    // MARK: - Confidence (per bundle id)

    func readConfidence(bundleID: String) -> Int {
        let url = confidenceURL(bundleID: bundleID)
        guard let s = try? String(contentsOf: url, encoding: .utf8),
              let n = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 50 // unknown apps start at neutral 50
        }
        return max(0, min(100, n))
    }

    func adjustConfidence(bundleID: String, delta: Int) {
        let current = readConfidence(bundleID: bundleID)
        let next = max(0, min(100, current + delta))
        try? String(next).write(to: confidenceURL(bundleID: bundleID), atomically: true, encoding: .utf8)
    }

    private func confidenceURL(bundleID: String) -> URL {
        baseURL.appendingPathComponent("wiki/apps/\(Self.slug(bundleID)).confidence")
    }

    // MARK: - Wiki read/write

    func readAppWiki(bundleID: String) -> String? {
        let url = baseURL.appendingPathComponent("wiki/apps/\(Self.slug(bundleID)).md")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Replace the full wiki page for an app. Typically called after the LLM
    /// compiles a new page from raw sessions.
    func writeAppWiki(bundleID: String, markdown: String) {
        let url = baseURL.appendingPathComponent("wiki/apps/\(Self.slug(bundleID)).md")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
        appendLog("compiled wiki/apps/\(Self.slug(bundleID)).md")
    }

    func appendLog(_ message: String) {
        let line = "- [\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        appendLine(line, to: baseURL.appendingPathComponent("wiki/log.md"))
    }

    // MARK: - Index + lint

    /// Rewrites `wiki/index.md` as a simple TOC of compiled app pages with
    /// their current confidence scores. Cheap — no LLM needed.
    func writeIndex() {
        let dir = baseURL.appendingPathComponent("wiki/apps", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "md" } ?? []

        var lines: [String] = [
            "# Anna Wiki Index",
            "",
            "_\(ISO8601DateFormatter().string(from: Date()))_",
            "",
        ]
        if files.isEmpty {
            lines.append("No app wikis compiled yet.")
        } else {
            lines.append("| App | Confidence | File |")
            lines.append("|---|---:|---|")
            for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let slug = url.deletingPathExtension().lastPathComponent
                let confURL = baseURL.appendingPathComponent("wiki/apps/\(slug).confidence")
                let conf = (try? String(contentsOf: confURL, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "–"
                lines.append("| \(slug) | \(conf) | [link](apps/\(url.lastPathComponent)) |")
            }
        }
        let content = lines.joined(separator: "\n") + "\n"
        try? content.write(to: baseURL.appendingPathComponent("wiki/index.md"),
                           atomically: true, encoding: .utf8)
    }

    /// Runs a cheap structural lint over every compiled app page and appends
    /// a report block to `wiki/log.md`. The LLM-compilation step is
    /// deliberately not invoked here — this is the "test suite" pass.
    ///
    /// Checks:
    ///   - page has required sections per schema
    ///   - no session in 90+ days → flag stale
    ///   - confidence below the floor (40) → flag low-confidence
    func lint() {
        let dir = baseURL.appendingPathComponent("wiki/apps", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "md" } ?? []

        var report: [String] = []
        report.append("## Lint \(ISO8601DateFormatter().string(from: Date()))")

        let requiredSections = ["## Overview", "## First launch", "## Key workflows",
                                "## Common confusions", "## Keyboard shortcuts", "## Confidence"]
        let now = Date()
        let staleWindow: TimeInterval = 90 * 24 * 60 * 60

        if files.isEmpty {
            report.append("- no app wikis yet")
        }

        for url in files {
            let slug = url.deletingPathExtension().lastPathComponent
            let md = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            var issues: [String] = []

            for sec in requiredSections where !md.contains(sec) {
                issues.append("missing \(sec)")
            }

            let bid = slug.replacingOccurrences(of: "-", with: ".")
            let conf = readConfidence(bundleID: bid)
            if conf < 40 { issues.append("confidence=\(conf) (below floor)") }

            // Stale check: any raw session for this bundle id in the last 90 days?
            let sessions = recentSessions(bundleID: bid, limit: 1)
            if let latest = sessions.first {
                if now.timeIntervalSince(latest.timestamp) > staleWindow {
                    issues.append("stale (>90 days since last session)")
                }
            } else {
                issues.append("no raw sessions on record")
            }

            if issues.isEmpty {
                report.append("- \(slug): ok (confidence=\(conf))")
            } else {
                report.append("- \(slug): " + issues.joined(separator: "; "))
            }
        }
        report.append("")

        appendLogBlock(report.joined(separator: "\n") + "\n")
    }

    private func appendLogBlock(_ block: String) {
        let url = baseURL.appendingPathComponent("wiki/log.md")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(block.utf8))
            }
        } else {
            try? block.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Schema access (fed into the compile prompt)

    func schemaText() -> String {
        let url = baseURL.appendingPathComponent("schema.md")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? Self.defaultSchema
    }

    // MARK: - Helpers

    private func appendLine(_ line: String, to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            }
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func slug(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
    }

    static let defaultSchema = """
    # Anna Knowledge Base Schema

    ## Page types
    - App pages (`wiki/apps/[bundle-id].md`): everything Anna knows about a specific app.
    - Gap pages (`raw/gaps/[bundle-id].md`): unsolved user questions worth investigating.

    ## App page structure
    Each app page must have:
    - `## Overview` — what this app is for, user personas
    - `## First launch` — the 5 most important things to show a new user
    - `## Key workflows` — task-oriented sections (not UI-section-oriented)
    - `## Common confusions` — things users get stuck on frequently
    - `## Keyboard shortcuts` — the most valuable 10
    - `## Confidence` — 0–100 score. Below 40 = unreliable, flag for improvement.

    ## Ingest rules
    - Every completed session is stored in `raw/sessions/` as JSON.
    - When a query is answered well (user continued the task), extract the insight and update `wiki/apps/[bundle-id].md`.
    - When a query fails (dismissed, ignored, or asked again), log to `raw/gaps/`.
    - Never delete from `raw/`. Only add.
    - Wiki pages get recompiled (not just appended) when confidence drops, or when 5+ new sessions accumulate for that app.

    ## Lint rules (run weekly)
    - Every app page has all required sections.
    - Flag any claim not confirmed by a session in 90+ days as stale.
    - Check for contradictions across app pages.
    - Output lint report to `wiki/log.md`.

    ## Confidence scoring
    - +5 for each session where advice was followed
    - +10 for each successful walkthrough completion
    - -10 for each gap logged against this app
    - -5 for each dismissed tip

    ## Anti-hallucination rule
    If an app's confidence is below 40, do not surface proactive tips for it —
    log a gap instead. A gap is better than a hallucinated tip.
    """
}
