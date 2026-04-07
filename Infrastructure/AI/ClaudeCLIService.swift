import Foundation

/// Wraps the local `claude` CLI in headless mode (--print) to handle complex
/// automation tasks and teaching interactions. Claude Code has full access to
/// bash, AppleScript, browser control, file operations, and web access.
actor ClaudeCLIService {
    private let claudePath: String
    private let timeoutSeconds: Double

    private let systemPrompt = """
    You are Anna, a friendly and knowledgeable macOS assistant. You help the user accomplish tasks AND teach them how things work.

    PERSONALITY:
    - Write the way you'd actually talk — short sentences, natural language.
    - Be playful, curious, and encouraging.
    - When teaching, explain concepts simply and suggest what to explore next.
    - For the ear, not the eye — your responses will be spoken aloud.

    RULES:
    1. DO the task — don't just explain how. Actually execute commands.
    2. Use `osascript` for AppleScript (Safari, Chrome, Music, Finder, System Events, etc.)
    3. Use `open` command for URLs and apps.
    4. For YouTube: open the specific video URL directly.
    5. For web scraping: use `curl` and parse the output.
    6. Keep responses conversational and concise (2-3 sentences max for actions).
    7. Never ask questions — just execute.
    8. If something fails, try an alternative approach.
    9. For purchases or financial transactions: describe what you would do but DO NOT execute.

    TEACHING MODE:
    When the user asks "how do I...", "what is...", "show me...", "teach me...", or similar:
    - Explain the concept in simple, spoken language.
    - If it involves something on screen, tell them exactly where to look and what to click.
    - Use [POINT:x,y:label] to point at UI elements on their screen.
    - Suggest a next step they could try to learn more.

    POINTING RULES:
    - When helping with app navigation, finding menus/buttons, or showing how to access features, include a [POINT:x,y:label] coordinate.
    - Only point at the center 60% of the screen (between 20%-80% of width and height).
    - Don't point at dock icons, menu bar items, or screen edges.
    - If no pointing is needed (general knowledge questions), append [POINT:none].
    - Coordinates should be absolute screen pixels.
    - Format: [POINT:x,y:label] where label describes what you're pointing at.
    - Err on the side of pointing rather than NOT pointing.

    SCREENSHOT CONTEXT:
    When a screenshot is provided, analyze what's on screen to give contextual help.
    Reference specific UI elements, windows, and content visible in the screenshot.
    """

    init(claudePath: String = "/Users/damienjacob/.local/bin/claude", timeoutSeconds: Double = 120) {
        self.claudePath = claudePath
        self.timeoutSeconds = timeoutSeconds
    }

    func execute(
        userRequest: String,
        screenshotPath: String? = nil,
        conversationContext: String? = nil
    ) async throws -> ClaudeCLIResult {
        let startTime = Date()

        // Build the prompt with context
        var fullPrompt = ""
        if let context = conversationContext {
            fullPrompt += "Previous conversation:\n\(context)\n\n"
        }
        if let screenshot = screenshotPath {
            fullPrompt += "(A screenshot of the user's current screen has been saved at: \(screenshot). Analyze it for context.)\n\n"
        }
        fullPrompt += userRequest

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = [
            "-p", fullPrompt,
            "--dangerously-skip-permissions",
            "--system-prompt", systemPrompt,
            "--output-format", "json",
            "--model", "sonnet",
            "--no-session-persistence",
        ]

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw AnnaError.claudeCLIFailed("Failed to launch claude: \(error.localizedDescription)")
        }

        let completed = await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [timeoutSeconds] in
                let deadline = DispatchTime.now() + timeoutSeconds
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    process.waitUntilExit()
                    group.leave()
                }
                let result = group.wait(timeout: deadline)
                if result == .timedOut {
                    process.terminate()
                    continuation.resume(returning: false)
                } else {
                    continuation.resume(returning: true)
                }
            }
        }

        guard completed else {
            throw AnnaError.claudeCLITimeout
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

        guard process.terminationStatus == 0 else {
            let errorMsg = stderr.isEmpty ? "Exit code \(process.terminationStatus)" : stderr
            throw AnnaError.claudeCLIFailed(errorMsg.prefix(500).description)
        }

        return parseJSONOutput(stdout, durationMs: durationMs, stderr: stderr)
    }

    private func parseJSONOutput(_ json: String, durationMs: Int, stderr: String) -> ClaudeCLIResult {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let text = json.trimmingCharacters(in: .whitespacesAndNewlines)
            return ClaudeCLIResult(
                text: text.isEmpty ? "Command executed." : text,
                success: true,
                costUSD: nil,
                durationMs: durationMs
            )
        }

        let resultText = obj["result"] as? String ?? "Done."
        let costUSD = obj["cost_usd"] as? Double
        let isError = (obj["subtype"] as? String) == "error_max_turns"

        return ClaudeCLIResult(
            text: resultText,
            success: !isError,
            costUSD: costUSD,
            durationMs: durationMs
        )
    }
}
