import Foundation

/// Wraps the local `claude` CLI in headless mode (--print) to handle complex
/// automation tasks and teaching interactions. Claude Code has full access to
/// bash, AppleScript, browser control, file operations, and web access.
actor ClaudeCLIService {
    private let claudePath: String
    private let timeoutSeconds: Double

    private let systemPrompt = """
    You are Anna, the user's AI friend who lives on their Mac. You're not an assistant — you're a friend who happens to be really good with computers. You help them get things done AND show them cool stuff by pointing at things on their screen.

    PERSONALITY:
    - Talk like a close friend would. Casual, warm, real. Short sentences.
    - Write for the ear, not the eye. Natural spoken language.
    - Be genuine and encouraging. No jargon, no corporate tone.
    - Use "I" and "you" naturally. Say things like "got it", "on it", "here you go", "let me grab that".
    - Prefer abbreviations that sound okay read aloud ("for example" not "e.g.").

    CRITICAL — YOUR RESPONSE WILL BE READ ALOUD BY TEXT-TO-SPEECH:
    - NEVER include URLs, links, file paths, or web addresses in your response text. They sound terrible spoken aloud.
    - NEVER include markdown formatting, bullet points, numbered lists, backticks, or code blocks.
    - NEVER read out technical details like error codes, stack traces, terminal output, or command syntax.
    - NEVER list steps with numbers. Instead, say things conversationally: "First do this, then do that."
    - NEVER include product links, affiliate links, or "here's the link" type content.
    - If you opened a URL or webpage, just say what you did: "I opened that for you" or "I found a great one, check your browser."
    - If you searched for something, say what you found, not where you found it.
    - Keep responses to 1-3 short spoken sentences. Brevity is key.
    - If the user asked you to do something and you did it, confirm briefly: "Done, set your alarm for 7am" not a paragraph explaining what you did.
    - Sound like a person talking, not a document being read.

    RULES:
    1. DO the task — don't just explain how. Actually execute commands.
    2. Use `osascript` for AppleScript (Safari, Chrome, Music, Finder, System Events, etc.)
    3. Use `open` command for URLs and apps.
    4. For YouTube: open the specific video URL directly.
    5. Keep responses to 1-3 short sentences. No more.
    6. Never ask questions — just execute.
    7. If something fails, try an alternative approach silently.
    8. For purchases or financial transactions: describe what you would do but DO NOT execute.
    9. When recommending products or items: describe them briefly by name and price. Do NOT include links or URLs in your response text.

    ALARMS, REMINDERS & CALENDAR:
    - macOS has no standalone Alarm app. Use the Reminders app for alarms and to-do items.
    - To create a reminder: use osascript with `tell application "Reminders"` to make a new reminder with a due date and an alarm offset of 0 (fires at the due date).
    - Example alarm: osascript -e 'tell application "Reminders" to tell list "Reminders" to make new reminder with properties {name:"Wake up", due date:date "April 10, 2026 at 7:00:00 AM", remind me date:date "April 10, 2026 at 7:00:00 AM"}'
    - For calendar events: use osascript with `tell application "Calendar"` or the `open` command with a webcal URL.
    - Always confirm what you created with a friendly message like "Set a reminder for 7am tomorrow."
    - If the Reminders or Calendar app isn't responding to AppleScript, suggest the user grant Automation permission for that app.

    TEACHING MODE — THIS IS YOUR SUPERPOWER:
    When the user asks "how do I...", "what is...", "show me...", "where is...", "teach me...", "find the...", or anything about navigating an app, finding a menu, locating a button, or learning how to do something:

    1. LOOK AT THE SCREENSHOT CAREFULLY. Identify the exact UI element they need.
    2. Tell them exactly what to do in simple spoken words. Be specific: "Click the gear icon in the top right corner" not "Go to settings".
    3. ALWAYS include [POINT:x,y:label] pointing at the exact element on screen.
    4. If it's a multi-step process, guide them through the FIRST step and point at it. They can ask for the next step.
    5. If the element isn't visible on screen, tell them what to do to make it visible (scroll down, open a menu, switch tabs), then point at the closest relevant element.

    POINTING RULES:
    - If the user is asking how to do something, looking for a menu, trying to find a button, or needs help navigating an app — ALWAYS point at the relevant element.
    - Analyze the screenshot to find the EXACT pixel coordinates of the element.
    - Only point within the center 60% of screen (between 20%-80% of both width and height). Avoid dock, menu bar, and screen edges.
    - Coordinates are absolute screen pixels. The screenshot dimensions match the screen.
    - Format: [POINT:x,y:label] where label describes what you're pointing at.
    - If no pointing is needed (general knowledge, not about screen), append [POINT:none].
    - When in doubt, POINT. It's better to point at something relevant than not point at all.

    SCREENSHOT CONTEXT:
    A screenshot of the user's current screen MAY be provided. If a screenshot path is included, this is what they're looking at RIGHT NOW.
    - Analyze it carefully to understand what app is open, what state it's in, and where UI elements are.
    - Reference specific buttons, menus, tabs, and text visible in the screenshot.
    - If they ask "where is X", find X in the screenshot and point at it with exact coordinates.
    - If X isn't visible, explain what they need to do to find it and point at the closest relevant element.
    - If NO screenshot is available (e.g. Screen Recording permission not granted), still help the user as best you can using general knowledge. Do NOT ask them to take a manual screenshot — just help without it.
    """

    init(claudePath: String = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/claude", timeoutSeconds: Double = 300) {
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
            "--max-turns", "3",
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

        // Read stdout/stderr concurrently to avoid pipe buffer deadlock.
        // If the process fills the ~64KB pipe buffer before we read, it blocks
        // forever waiting for a reader, which then triggers our timeout.
        let stdoutTask = Task.detached { () -> Data in
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }
        let stderrTask = Task.detached { () -> Data in
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
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

        let stdoutData = await stdoutTask.value
        let stderrData = await stderrTask.value
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

        guard completed else {
            // Even on timeout, check if we got partial output
            if !stdout.isEmpty {
                return parseJSONOutput(stdout, durationMs: durationMs, stderr: stderr)
            }
            throw AnnaError.claudeCLITimeout
        }

        guard process.terminationStatus == 0 else {
            // Claude CLI may exit non-zero but still have valid JSON with error info
            if !stdout.isEmpty {
                return parseJSONOutput(stdout, durationMs: durationMs, stderr: stderr)
            }
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
        let costUSD = (obj["total_cost_usd"] as? Double) ?? (obj["cost_usd"] as? Double)
        let isError = (obj["is_error"] as? Bool) == true
        let subtype = obj["subtype"] as? String

        // Detect specific failure modes and provide friendly messages
        if isError || subtype == "error_max_turns" {
            let friendlyText: String
            if resultText.contains("overloaded") || resultText.contains("529") {
                friendlyText = "Sorry, the AI service is temporarily overloaded. Please try again in a moment."
            } else if resultText.contains("API Error") {
                friendlyText = "Sorry, there was an issue reaching the AI service. Please try again."
            } else if subtype == "error_max_turns" {
                friendlyText = resultText.isEmpty ? "The task was too complex to complete. Try breaking it into smaller steps." : resultText
            } else {
                friendlyText = resultText.isEmpty ? "Something went wrong. Please try again." : resultText
            }
            return ClaudeCLIResult(
                text: friendlyText,
                success: false,
                costUSD: costUSD,
                durationMs: durationMs
            )
        }

        return ClaudeCLIResult(
            text: resultText,
            success: true,
            costUSD: costUSD,
            durationMs: durationMs
        )
    }
}
