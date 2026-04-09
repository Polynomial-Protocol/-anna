import AppKit
import CoreGraphics
import Foundation

@MainActor
final class DirectActionExecutor {

    func execute(_ action: DirectAction) async throws -> AutomationOutcome {
        switch action {
        case .mediaControl(let command):
            return executeMediaControl(command)
        case .openApp(let name):
            return executeOpenApp(name)
        case .systemControl(let command):
            return try executeSystemControl(command)
        case .playOnYouTube(let query):
            return await executePlayOnYouTube(query)
        case .playOnSpotify(let query):
            return executePlayOnSpotify(query)
        case .playOnAppleMusic(let query):
            return executePlayOnAppleMusic(query)
        case .searchWeb(let query):
            return executeSearchWeb(query)
        case .openURL(let url):
            return executeOpenURL(url)
        }
    }

    // MARK: - YouTube Playback

    private func executePlayOnYouTube(_ query: String) async -> AutomationOutcome {
        let searchTerms = improveYouTubeQuery(query)
        guard let encoded = searchTerms.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return .blocked(summary: "Could not encode query.")
        }

        let searchURL = "https://www.youtube.com/results?search_query=\(encoded)"
        let browser = detectBrowser()
        let opened = openURLInBrowser(searchURL, browser: browser)
        guard opened else {
            return .blocked(summary: "Could not open browser.")
        }

        // Try multiple times with increasing delays to find and play the first video
        for attempt in 0..<3 {
            let delay: UInt64 = UInt64(3 + attempt * 2) * 1_000_000_000
            try? await Task.sleep(nanoseconds: delay)

            // Strategy 1: JS extraction (most reliable when JS is enabled)
            let extractJS = "(function(){var a=document.querySelector('a#video-title');if(a&&a.href)return a.href;var b=document.querySelectorAll('a');for(var i=0;i<b.length;i++){if(b[i].href&&b[i].href.indexOf('/watch?v=')>-1)return b[i].href}return ''})()"
            let videoURL = executeJSInBrowser(extractJS, browser: browser)

            if !videoURL.isEmpty && videoURL.contains("/watch?v=") {
                // Navigate to the video in the SAME tab (not a new one)
                navigateCurrentTab(to: videoURL, browser: browser)
                return .completed(summary: "Playing \"\(query)\" on YouTube.", openedURL: URL(string: videoURL))
            }

            // Strategy 2: Get page source and regex-parse
            if let firstVideoURL = extractFirstVideoURLFromPageSource(browser: browser) {
                navigateCurrentTab(to: firstVideoURL, browser: browser)
                return .completed(summary: "Playing \"\(query)\" on YouTube.", openedURL: URL(string: firstVideoURL))
            }
        }

        return .completed(summary: "Opened YouTube search for \"\(query)\". Couldn't auto-play first result.", openedURL: URL(string: searchURL))
    }

    /// Navigate the current active tab to a URL (instead of opening a new tab)
    private func navigateCurrentTab(to urlString: String, browser: BrowserType) {
        let script: String
        switch browser {
        case .chrome:
            script = """
            tell application "Google Chrome"
                set URL of active tab of front window to "\(urlString)"
            end tell
            """
        case .safari:
            script = """
            tell application "Safari"
                set URL of current tab of front window to "\(urlString)"
            end tell
            """
        }
        runAppleScript(script)
    }

    private func improveYouTubeQuery(_ query: String) -> String {
        let q = query.lowercased()
        // If the query is very generic, make it better
        if q == "some songs" || q == "songs" || q == "music" {
            return "top songs 2024 playlist"
        }
        if q == "top songs" || q == "top music" || q == "popular songs" {
            return "top songs 2024 hits"
        }
        if q == "new songs" || q == "latest songs" || q == "new music" {
            return "new songs 2024 latest hits"
        }
        return query
    }

    // MARK: - Web Search

    private func executeSearchWeb(_ query: String) -> AutomationOutcome {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return .blocked(summary: "Could not encode search query.")
        }
        let url = "https://www.google.com/search?q=\(encoded)"
        let browser = detectBrowser()
        let opened = openURLInBrowser(url, browser: browser)
        return opened
            ? .completed(summary: "Searched for \"\(query)\".", openedURL: URL(string: url))
            : .blocked(summary: "Could not open browser for search.")
    }

    // MARK: - Spotify Playback

    private func executePlayOnSpotify(_ query: String) -> AutomationOutcome {
        // Use Spotify's search URI scheme: spotify:search:<query>
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return .blocked(summary: "Could not encode query.")
        }

        // Try Spotify URI scheme first (opens directly in Spotify app)
        if let spotifyURL = URL(string: "spotify:search:\(encoded)"),
           NSWorkspace.shared.urlForApplication(toOpen: spotifyURL) != nil {
            NSWorkspace.shared.open(spotifyURL)
            return .completed(summary: "Searching \"\(query)\" in Spotify.", openedURL: spotifyURL)
        }

        // Fallback: open Spotify web search
        let webURL = "https://open.spotify.com/search/\(encoded)"
        let browser = detectBrowser()
        let opened = openURLInBrowser(webURL, browser: browser)
        return opened
            ? .completed(summary: "Searching \"\(query)\" in Spotify.", openedURL: URL(string: webURL))
            : .blocked(summary: "Could not open Spotify.")
    }

    // MARK: - Apple Music Playback

    private func executePlayOnAppleMusic(_ query: String) -> AutomationOutcome {
        // Use AppleScript to search and play in Music app
        let escapedQuery = query.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Music"
            activate
        end tell
        """
        runAppleScript(script)

        // Open Apple Music web search as a reliable fallback
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return .blocked(summary: "Could not encode query.")
        }
        let webURL = "https://music.apple.com/search?term=\(encoded)"
        let browser = detectBrowser()
        let opened = openURLInBrowser(webURL, browser: browser)
        return opened
            ? .completed(summary: "Searching \"\(query)\" in Apple Music.", openedURL: URL(string: webURL))
            : .completed(summary: "Opened Music app for \"\(query)\".", openedURL: nil)
    }

    // MARK: - Open URL

    private func executeOpenURL(_ url: String) -> AutomationOutcome {
        var fullURL = url
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            fullURL = "https://\(url)"
        }
        guard let nsURL = URL(string: fullURL) else {
            return .blocked(summary: "Invalid URL: \(url)")
        }
        NSWorkspace.shared.open(nsURL)
        return .completed(summary: "Opened \(url).", openedURL: nsURL)
    }

    // MARK: - Media Control

    private func executeMediaControl(_ command: String) -> AutomationOutcome {
        let keyCode: Int
        switch command.lowercased() {
        case "play", "resume":
            keyCode = Int(NX_KEYTYPE_PLAY)
        case "pause", "stop":
            keyCode = Int(NX_KEYTYPE_PLAY) // Same key — NX_KEYTYPE_PLAY is a toggle
        case "next", "next track", "skip":
            keyCode = Int(NX_KEYTYPE_NEXT)
        case "previous", "previous track":
            keyCode = Int(NX_KEYTYPE_PREVIOUS)
        default:
            return .blocked(summary: "Unknown media command: \(command)")
        }
        postMediaKey(keyCode: keyCode)
        return .completed(summary: "Media: \(command)", openedURL: nil)
    }

    private func postMediaKey(keyCode: Int) {
        func doKey(down: Bool) {
            let flags: Int = (down ? 0xa00 : 0xb00)
            let data1 = (keyCode << 16) | flags
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ) else { return }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
        doKey(down: true)
        doKey(down: false)
    }

    // MARK: - Open App

    private func executeOpenApp(_ name: String) -> AutomationOutcome {
        // Try direct launch
        if NSWorkspace.shared.launchApplication(name) {
            return .completed(summary: "Opened \(name).", openedURL: nil)
        }
        // Try common bundle ID patterns
        let guesses = [
            "com.apple.\(name.lowercased())",
            "com.apple.\(name.capitalized)",
            "com.google.\(name.capitalized)",
        ]
        for bundleID in guesses {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
                return .completed(summary: "Opened \(name).", openedURL: nil)
            }
        }
        return .blocked(summary: "Could not find app: \(name)")
    }

    // MARK: - System Control

    private func executeSystemControl(_ command: String) throws -> AutomationOutcome {
        switch command {
        case "volume_up":
            runAppleScript("set volume output volume ((output volume of (get volume settings)) + 10)")
            return .completed(summary: "Volume up.", openedURL: nil)
        case "volume_down":
            runAppleScript("set volume output volume ((output volume of (get volume settings)) - 10)")
            return .completed(summary: "Volume down.", openedURL: nil)
        case "mute":
            runAppleScript("set volume output muted true")
            return .completed(summary: "Muted.", openedURL: nil)
        case "unmute":
            runAppleScript("set volume output muted false")
            return .completed(summary: "Unmuted.", openedURL: nil)
        case "lock":
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["displaysleepnow"]
            try process.run()
            return .completed(summary: "Screen locked.", openedURL: nil)
        case "sleep":
            runAppleScript("tell application \"System Events\" to sleep")
            return .completed(summary: "Putting Mac to sleep.", openedURL: nil)
        default:
            return .blocked(summary: "Unknown system command: \(command)")
        }
    }

    // MARK: - Browser Helpers

    private enum BrowserType {
        case chrome, safari
    }

    private func detectBrowser() -> BrowserType {
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil {
            return .chrome
        }
        return .safari
    }

    private func openURLInBrowser(_ urlString: String, browser: BrowserType) -> Bool {
        let script: String
        switch browser {
        case .chrome:
            script = """
            tell application "Google Chrome"
                activate
                if (count of windows) = 0 then
                    make new window
                end if
                tell front window
                    make new tab with properties {URL:"\(urlString)"}
                end tell
            end tell
            """
        case .safari:
            script = """
            tell application "Safari"
                activate
                if (count of windows) = 0 then
                    make new document
                end if
                tell front window
                    set current tab to (make new tab with properties {URL:"\(urlString)"})
                end tell
            end tell
            """
        }

        if runAppleScript(script) {
            return true
        }
        // Fallback to NSWorkspace
        if let url = URL(string: urlString) {
            return NSWorkspace.shared.open(url)
        }
        return false
    }

    /// Extracts the first YouTube video URL from the current page source using AppleScript (no JS permissions needed).
    private func extractFirstVideoURLFromPageSource(browser: BrowserType) -> String? {
        let script: String
        switch browser {
        case .chrome:
            script = """
            tell application "Google Chrome"
                tell active tab of front window
                    return URL
                end tell
            end tell
            """
        case .safari:
            script = """
            tell application "Safari"
                return URL of current tab of front window
            end tell
            """
        }

        // First verify we're on a YouTube search page
        let currentURL = runAppleScriptReturning(script) ?? ""
        guard currentURL.contains("youtube.com/results") else { return nil }

        // Use JS to get the first video link — IIFE to ensure a return value
        let jsScript = "(function(){var a=document.querySelector('a#video-title');if(a&&a.href)return a.href;var l=document.querySelectorAll('a');for(var i=0;i<l.length;i++){if(l[i].href&&l[i].href.indexOf('/watch?v=')>-1)return l[i].href}return ''})()"
        let result = executeJSInBrowser(jsScript, browser: browser)
        if !result.isEmpty && result.contains("/watch?v=") {
            return result
        }

        // Last resort: use AppleScript to get page source and regex-parse video URLs
        let sourceScript: String
        switch browser {
        case .chrome:
            sourceScript = """
            tell application "Google Chrome"
                tell active tab of front window
                    return execute javascript "document.documentElement.outerHTML.substring(0,50000)"
                end tell
            end tell
            """
        case .safari:
            sourceScript = """
            tell application "Safari"
                return source of front document
            end tell
            """
        }

        guard let source = runAppleScriptReturning(sourceScript) else { return nil }

        // Parse first /watch?v= URL from page source
        let pattern = #"/watch\?v=[a-zA-Z0-9_-]{11}"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let range = Range(match.range, in: source) else {
            return nil
        }

        return "https://www.youtube.com\(source[range])"
    }

    private func executeJSInBrowser(_ js: String, browser: BrowserType) -> String {
        // Collapse to single line and escape for AppleScript string embedding
        let singleLine = js.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let escapedJS = singleLine.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script: String
        switch browser {
        case .chrome:
            script = """
            tell application "Google Chrome"
                tell active tab of front window
                    set result to execute javascript "\(escapedJS)"
                    return result as text
                end tell
            end tell
            """
        case .safari:
            script = """
            tell application "Safari"
                tell front document
                    set result to do JavaScript "\(escapedJS)"
                    return result as text
                end tell
            end tell
            """
        }

        return runAppleScriptReturning(script) ?? ""
    }

    private func runAppleScriptReturning(_ source: String) -> String? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let output = script?.executeAndReturnError(&error)
        return output?.stringValue
    }

    @discardableResult
    private func runAppleScript(_ source: String) -> Bool {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        _ = script?.executeAndReturnError(&error)
        return error == nil
    }
}
