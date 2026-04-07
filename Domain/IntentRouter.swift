import Foundation

enum IntentRouter {
    static func route(_ transcript: String) -> ExecutionTier {
        let text = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .agent(transcript) }

        // Tier 1: Media controls (bare commands — no object)
        let bareMediaCommands = ["play", "pause", "stop", "resume", "next", "next track",
                                 "previous", "previous track", "skip"]
        if bareMediaCommands.contains(text) {
            return .direct(.mediaControl(command: text))
        }

        // Tier 1: System controls
        let systemPatterns: [(pattern: String, command: String)] = [
            ("volume up", "volume_up"),
            ("volume down", "volume_down"),
            ("mute", "mute"),
            ("unmute", "unmute"),
            ("lock screen", "lock"),
            ("lock my mac", "lock"),
            ("sleep", "sleep"),
        ]
        for (pattern, command) in systemPatterns {
            if text == pattern || text == pattern + " please" {
                return .direct(.systemControl(command: command))
            }
        }

        // Tier 1: Open app (simple "open <app>")
        if text.hasPrefix("open ") {
            let rest = String(text.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            let words = rest.split(separator: " ")
            if words.count <= 3 && !rest.contains(" and ") && !rest.contains(" then ") {
                // Check if it looks like a URL
                if rest.contains(".") && !rest.contains(" ") {
                    return .direct(.openURL(url: rest))
                }
                return .direct(.openApp(name: rest))
            }
        }

        // Tier 1: Play on YouTube — "play X on youtube", "play X in youtube",
        // "play some songs", "play top songs", "play music"
        if text.hasPrefix("play ") {
            let query = String(text.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            // If it mentions YouTube or is a music/song/video query
            if text.contains("youtube") || text.contains("you tube") {
                let cleanQuery = query
                    .replacingOccurrences(of: "on youtube", with: "")
                    .replacingOccurrences(of: "in youtube", with: "")
                    .replacingOccurrences(of: "on you tube", with: "")
                    .trimmingCharacters(in: .whitespaces)
                return .direct(.playOnYouTube(query: cleanQuery.isEmpty ? "top songs" : cleanQuery))
            }
            // Generic "play X" — treat as YouTube if it sounds like media
            let mediaKeywords = ["song", "songs", "music", "video", "movie", "track", "album",
                                 "playlist", "top", "latest", "new", "best", "favorites",
                                 "hits", "trending", "popular"]
            if mediaKeywords.contains(where: { query.contains($0) }) {
                return .direct(.playOnYouTube(query: query))
            }
            // "play [artist/song name]" — also YouTube
            if !query.isEmpty {
                return .direct(.playOnYouTube(query: query))
            }
        }

        // Tier 1: Web search — "search for X", "google X", "look up X"
        if let query = extractSearchQuery(text) {
            return .direct(.searchWeb(query: query))
        }

        // Tier 2: Everything else → Claude CLI
        return .agent(transcript)
    }

    private static func extractSearchQuery(_ text: String) -> String? {
        let searchPrefixes = [
            "search for ", "search ", "google ", "look up ",
            "look for ", "find ", "search the web for ",
        ]
        for prefix in searchPrefixes {
            if text.hasPrefix(prefix) {
                let query = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                if !query.isEmpty { return query }
            }
        }
        return nil
    }

    static func normalize(_ transcript: String) -> String {
        transcript
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
    }
}
