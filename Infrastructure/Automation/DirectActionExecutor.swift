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
        case .searchWeb(let query):
            return executeSearchWeb(query)
        case .openURL(let url):
            return executeOpenURL(url)
        }
    }

    // MARK: - YouTube Playback

    private func executePlayOnYouTube(_ query: String) async -> AutomationOutcome {
        // Build a smart search query
        let searchTerms = improveYouTubeQuery(query)
        guard let encoded = searchTerms.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return .blocked(summary: "Could not encode query.")
        }

        let searchURL = "https://www.youtube.com/results?search_query=\(encoded)"

        // Open the search page in the browser
        let browser = detectBrowser()
        let opened = openURLInBrowser(searchURL, browser: browser)
        guard opened else {
            return .blocked(summary: "Could not open browser.")
        }

        // Wait for the page to load, then click the first video
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        // Use JavaScript to click the first video result
        let clickJS = """
        (function() {
            // Try to find the first video link
            var link = document.querySelector('a#video-title');
            if (link) { link.click(); return 'clicked'; }
            // Fallback: first thumbnail
            var thumb = document.querySelector('a#thumbnail');
            if (thumb) { thumb.click(); return 'clicked_thumb'; }
            return 'not_found';
        })()
        """

        let result = executeJSInBrowser(clickJS, browser: browser)

        if result.contains("clicked") {
            return .completed(summary: "Playing \"\(query)\" on YouTube.", openedURL: URL(string: searchURL))
        } else {
            // Fallback: at least the search page is open
            return .completed(summary: "Opened YouTube search for \"\(query)\". Couldn't auto-play first result.", openedURL: URL(string: searchURL))
        }
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
            keyCode = Int(NX_KEYTYPE_PLAY)
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

    private func executeJSInBrowser(_ js: String, browser: BrowserType) -> String {
        let escapedJS = js.replacingOccurrences(of: "\\", with: "\\\\")
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

        let nsScript = NSAppleScript(source: script)
        var error: NSDictionary?
        let output = nsScript?.executeAndReturnError(&error)
        return output?.stringValue ?? ""
    }

    @discardableResult
    private func runAppleScript(_ source: String) -> Bool {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        _ = script?.executeAndReturnError(&error)
        return error == nil
    }
}
