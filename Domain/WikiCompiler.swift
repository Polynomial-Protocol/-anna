import Foundation

/// Karpathy-style compile step: raw session logs → structured `wiki/apps/<slug>.md`.
///
/// Runs as a lightweight background task when ≥5 new sessions have accumulated
/// for a given app since the last compile. Uses the Anthropic messages API
/// directly (text-only, no tools, no vision) to keep the call cheap.
actor WikiCompiler {

    private let kb: WikiKnowledgeBase
    private let timeoutSeconds: Double

    init(kb: WikiKnowledgeBase = .shared, timeoutSeconds: Double = 60) {
        self.kb = kb
        self.timeoutSeconds = timeoutSeconds
    }

    /// Compile (or recompile) the wiki page for an app.
    /// Safe to call repeatedly — idempotent enough; at worst we pay one API
    /// call. No-op if no API key is configured or no raw sessions exist.
    func compileIfNeeded(bundleID: String, appName: String, force: Bool = false) async {
        let pending = await kb.countPendingSessions(bundleID: bundleID)
        guard force || pending >= 5 else { return }

        guard let apiKey = APIKeyStore.load(for: .anthropic), !apiKey.isEmpty else {
            await kb.appendLog("skip compile for \(bundleID): no Anthropic API key")
            return
        }

        let sessions = await kb.recentSessions(bundleID: bundleID, limit: 20)
        guard !sessions.isEmpty else { return }

        let existing = await kb.readAppWiki(bundleID: bundleID) ?? "Does not exist yet"
        let schema = await kb.schemaText()

        let sessionsBlock = sessions.map { log -> String in
            let ts = ISO8601DateFormatter().string(from: log.timestamp)
            return "### \(ts)\nUser: \(log.userQuery)\nAssistant: \(log.assistantReply)"
        }.joined(separator: "\n\n")

        let user = """
        You are Anna's knowledge compiler. Update the wiki page for \(appName) (\(bundleID)).

        EXISTING WIKI PAGE
        ---
        \(existing)
        ---

        NEW RAW SESSIONS (most recent first)
        ---
        \(sessionsBlock)
        ---

        SCHEMA RULES YOU MUST FOLLOW
        ---
        \(schema)
        ---

        Task:
        - Integrate any NEW genuine insights from the sessions.
        - Do NOT add speculative content. Only add things confirmed by the sessions.
        - Preserve any existing content that is still valid.
        - Update the `## Confidence` score based on session outcomes.
        - Follow the app page structure from the schema exactly.

        Return ONLY the complete updated wiki page as markdown. No preamble, no fences.
        """

        guard let markdown = await callAnthropicText(apiKey: apiKey, user: user) else {
            await kb.appendLog("compile failed for \(bundleID)")
            return
        }
        await kb.writeAppWiki(bundleID: bundleID, markdown: markdown)
        await kb.markCompiled(bundleID: bundleID)
    }

    // MARK: - Bare text-only Anthropic call (no tools, no vision).

    private func callAnthropicText(apiKey: String, user: String) async -> String? {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return nil }
        let body: [String: Any] = [
            "model": "claude-sonnet-4-5",
            "max_tokens": 2048,
            "messages": [
                ["role": "user", "content": user]
            ]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = timeoutSeconds
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            return nil
        }
        let texts = content.compactMap { block -> String? in
            guard let type = block["type"] as? String, type == "text",
                  let text = block["text"] as? String else { return nil }
            return text
        }
        let out = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }
}
