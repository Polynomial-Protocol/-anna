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

        // Tier 1: Play media — detect platform (Spotify, Apple Music, YouTube) or default to YouTube
        if text.hasPrefix("play ") {
            let query = String(text.dropFirst(5)).trimmingCharacters(in: .whitespaces)

            // Detect target platform from the command
            if text.contains("spotify") || text.contains("spotfy") {
                let cleanQuery = Self.removePlatformMention(query, platforms: ["spotify", "spotfy"])
                return .direct(.playOnSpotify(query: cleanQuery.isEmpty ? "top songs" : cleanQuery))
            }
            if text.contains("apple music") || text.contains("itunes") || text.contains("i tunes") {
                let cleanQuery = Self.removePlatformMention(query, platforms: ["apple music", "itunes", "i tunes"])
                return .direct(.playOnAppleMusic(query: cleanQuery.isEmpty ? "top songs" : cleanQuery))
            }
            if text.contains("youtube") || text.contains("you tube") {
                let cleanQuery = Self.removePlatformMention(query, platforms: ["youtube", "you tube"])
                return .direct(.playOnYouTube(query: cleanQuery.isEmpty ? "top songs" : cleanQuery))
            }

            // No platform specified — default to YouTube for media queries
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

    private static func removePlatformMention(_ query: String, platforms: [String]) -> String {
        var clean = query
        for platform in platforms {
            clean = clean
                .replacingOccurrences(of: "on \(platform)", with: "")
                .replacingOccurrences(of: "in \(platform)", with: "")
                .replacingOccurrences(of: "using \(platform)", with: "")
                .replacingOccurrences(of: "with \(platform)", with: "")
                .replacingOccurrences(of: platform, with: "")
        }
        return clean.trimmingCharacters(in: .whitespaces)
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
