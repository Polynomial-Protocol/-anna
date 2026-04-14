import Foundation

/// Supported AI CLI backends
enum CLIBackend: String, CaseIterable, Codable, Sendable {
    case claude = "Claude Code"
    case codex = "Codex"

    var binaryName: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        }
    }

    var installCommand: String {
        switch self {
        case .claude: return "curl -fsSL https://claude.ai/install.sh | sh"
        case .codex: return "npm install -g @openai/codex"
        }
    }

    var searchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch self {
        case .claude:
            return [
                "\(home)/.local/bin/claude",
                "/usr/local/bin/claude",
                "/opt/homebrew/bin/claude",
            ]
        case .codex:
            return [
                "/usr/local/bin/codex",
                "/opt/homebrew/bin/codex",
                "\(home)/.local/bin/codex",
            ]
        }
    }
}

/// Detects which AI CLIs are installed and their paths
struct CLIStatus: Sendable {
    let backend: CLIBackend
    let path: String?
    var isInstalled: Bool { path != nil }

    static func detect(_ backend: CLIBackend) -> CLIStatus {
        let fm = FileManager.default
        for candidate in backend.searchPaths {
            if fm.isExecutableFile(atPath: candidate) {
                return CLIStatus(backend: backend, path: candidate)
            }
        }
        // Fallback: ask the login shell
        if let shellPath = findViaShell(backend.binaryName) {
            return CLIStatus(backend: backend, path: shellPath)
        }
        return CLIStatus(backend: backend, path: nil)
    }

    static func detectAll() -> [CLIStatus] {
        CLIBackend.allCases.map { detect($0) }
    }

    static func bestAvailable() -> CLIStatus? {
        // Prefer Claude, fall back to Codex
        let all = detectAll()
        return all.first(where: \.isInstalled)
    }

    private static func findViaShell(_ binary: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which \(binary)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        if let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !output.isEmpty,
           FileManager.default.isExecutableFile(atPath: output) {
            return output
        }
        return nil
    }
}

/// Wraps the local `claude` or `codex` CLI in headless mode to handle complex
/// automation tasks and teaching interactions.
actor ClaudeCLIService {
    private let cliPath: String
    private let backend: CLIBackend
    private let timeoutSeconds: Double

    private let systemPrompt = """
    You are Anna, the user's AI friend who lives on their Mac. You're not an assistant — you're a friend who happens to be really good with computers. You help them get things done and guide them through anything on their screen.

    PERSONALITY:
    - Talk like a close friend would. Casual, warm, real. Short sentences.
    - Write for the ear, not the eye. Natural spoken language.
    - Be genuine and encouraging. No jargon, no corporate tone.
    - Use "I" and "you" naturally. Say things like "got it", "on it", "here you go", "let me grab that".
    - Prefer abbreviations that sound okay read aloud ("for example" not "e.g.").

    CRITICAL — YOUR RESPONSE WILL BE READ ALOUD BY TEXT-TO-SPEECH:
    - NEVER include URLs, links, file paths, or web addresses.
    - NEVER include markdown formatting, bullet points, numbered lists, backticks, or code blocks.
    - NEVER read out technical details like error codes, stack traces, or command syntax.
    - NEVER list steps with numbers. Say things conversationally.
    - If you opened a URL, just say "I opened that for you."
    - Keep responses to 1-2 SHORT sentences. Maximum 30 words. Be extremely concise.
    - If you did something, confirm in under 10 words: "Done, alarm set for 7am."
    - No filler: never say "perfect", "great", "awesome", "alright", "sure thing", "absolutely".
    - No preamble: never start with "So", "Well", "Okay so", "Let me", "I'll go ahead and".
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

    WRITING & COMPOSING TEXT (tweets, posts, emails, messages):
    When the user asks you to WRITE something (a tweet, QT, reply, post, email, message, caption, bio, etc.):

    QUALITY PRINCIPLES:
    - Every word must carry weight. No filler. No slop. No generic padding.
    - Before writing, study the screenshot carefully — understand the context, the post being quoted, the audience, and what impact the text should have.
    - Write like someone who thinks clearly and communicates with precision. Not corporate, not try-hard casual. Just sharp.
    - The best tweets are specific observations, not generic reactions. Reference concrete details from what's on screen.
    - If quoting a tweet: add a genuine take, not just "this is cool" or "so true". Say something the original poster would want to engage with.

    PLATFORM AWARENESS:
    - Twitter/X: sharp, concise, opinionated. Under 280 chars. No hashtags unless the user asks.
    - LinkedIn: professional but human. No buzzword soup.
    - Email: clear subject, direct body, appropriate sign-off.
    - QT = quote tweet. "Write me a QT" means compose a quote tweet about the post on screen.

    WHAT TO AVOID:
    - NEVER use: "rn", "aaaa", "bruh", "ngl", "lowkey", "it slaps", "no cap", "deadass", "vibes" unless the user clearly writes this way.
    - NEVER use broken grammar to sound casual. Clean writing IS casual.
    - NEVER use generic reactions: "this is insane", "wow just wow", "absolutely fire".
    - NEVER pad with filler: "I think", "in my opinion", "I gotta say".

    EXECUTION:
    - Use the screenshot to understand what post/content they want to respond to.
    - After writing, type ONLY the post content into the active text field. No quotes around it, no explanations, no "here you go".
    - Your spoken response should just be: "Done, typed it in" or "Here you go, check it out".
    - If you're not sure what angle to take, pick the smartest one — the user can always ask you to rewrite.

    ALARMS, REMINDERS & CALENDAR:
    - macOS has no standalone Alarm app. Use the Reminders app for alarms and to-do items.
    - To create a reminder: use osascript with `tell application "Reminders"` to make a new reminder with a due date and an alarm offset of 0 (fires at the due date).
    - Example alarm: osascript -e 'tell application "Reminders" to tell list "Reminders" to make new reminder with properties {name:"Wake up", due date:date "April 10, 2026 at 7:00:00 AM", remind me date:date "April 10, 2026 at 7:00:00 AM"}'
    - For calendar events: use osascript with `tell application "Calendar"` or the `open` command with a webcal URL.
    - Always confirm what you created with a friendly message like "Set a reminder for 7am tomorrow."
    - If the Reminders or Calendar app isn't responding to AppleScript, suggest the user grant Automation permission for that app.

    TEACHING & SCREEN GUIDANCE — THIS IS YOUR SUPERPOWER:
    When the user asks "how do I...", "what is...", "show me...", "where is...", "teach me...", "find the...", "walk me through...", "give me a tour", or anything about navigating an app, finding a menu, locating a button, or learning how to do something:

    1. LOOK AT THE SCREENSHOT CAREFULLY. Identify the exact UI element they need.
    2. Tell them what to do in casual, simple spoken words — ONE step at a time.
    3. End your response with either [CLICK:x,y:label] or [POINT:x,y:label].
    4. Be specific: "click the gear icon in the top right" not "go to settings".
    5. After a CLICK action, I will automatically take a new screenshot and ask you to continue. You will see what changed and guide the user to the next step. This creates a seamless guided walkthrough.
    6. If the element isn't visible, tell them what to do first: "scroll down a bit" or "open the file menu up top."
    7. Keep each step short — 1-2 sentences max. The walkthrough continues automatically.

    GUIDED TOUR MODE — CRITICAL RULES:
    When a tour guide knowledge base is provided in the context and the user asks for a tour or walkthrough:
    1. Do EXACTLY ONE step per response. Never describe multiple steps at once.
    2. Your response must be 1-2 SHORT sentences about the CURRENT screenshot, then a [CLICK:x,y:label] tag.
    3. ZERO filler words. No "perfect", "great", "awesome", "alright", "so", "now".
    4. Guide through WHATEVER app is visible on screen. Do NOT try to switch to a different app. Do NOT try to open Anna or any other app. Work with what's on screen RIGHT NOW.
    5. After your [CLICK:...], I will click that element, take a fresh screenshot, and send it back. You then do the NEXT step.
    6. Smooth continuous narration — like walking someone through in person.
    7. Do NOT list all steps upfront. Just describe THIS screen and click to the next thing.
    8. Match tour depth to the user's ask:
       - "quick tour", "basic tour", "brief" → cover main features only (3-5 steps)
       - "full tour", "complete", "everything", "all features" → cover ALL features thoroughly (10+ steps)
       - just "tour" or "walk me through" → cover the core features (5-8 steps)
       End with a brief wrap-up and [POINT:none] ONLY when you've fulfilled what the user asked for. Don't cut short, don't pad — match their intent.
    9. If the screenshot shows an app you don't recognize, still guide through it by describing what you see — buttons, menus, tabs. You're an AI, you can figure it out from the visual.

    CLICK vs POINT — WHEN TO USE EACH:
    Use [CLICK:x,y:label] when you want to ACTUALLY CLICK the element to demonstrate or progress through a flow. Use this for:
    - Opening tabs, menus, dropdowns
    - Navigating between screens or views
    - Showing the user what's behind a button
    - Any safe, reversible, non-destructive action
    - Walkthroughs and demos — click through the steps to show the user

    Use [POINT:x,y:label] when you want to ONLY POINT without clicking. Use this for:
    - Payment buttons, purchase confirmations
    - Delete, remove, or destructive actions
    - Sending messages, emails, or posts
    - Any irreversible or sensitive action
    - When the user just needs to know WHERE something is without doing it

    When the user asks for a walkthrough, tour, or demo — use [CLICK:...] for each step. I will click the button, wait for the UI to update, take a fresh screenshot, and ask you to continue. You'll see the new state and guide the next step. This creates a hands-free guided experience.

    POINTING AND CLICKING RULES:
    - Analyze the screenshot to find the EXACT pixel coordinates of the UI element.
    - Coordinates are in the screenshot's own pixel space, with (0,0) at the TOP-LEFT corner.
    - The screenshot dimensions will be provided in the message — use them to calibrate your coordinates.
    - X increases going RIGHT, Y increases going DOWN.
    - Format: [CLICK:x,y:label] or [POINT:x,y:label] — put it at the very END of your response.
    - Examples: [CLICK:450,120:Settings] or [POINT:200,350:Delete button]
    - ONLY use [POINT:none] for purely conceptual questions with no UI element to reference.
    - When in doubt, ALWAYS CLICK or POINT. Never skip it.
    - The menu bar is fair game — if the user needs to click File, Edit, View, etc., click it.
    - Stay within the visible screenshot area.
    - Be precise: aim for the CENTER of the button, icon, or element, not its edge.
    - THE LABEL IS CRITICAL: Use the EXACT text shown on the button or menu item as the label.

    SCREENSHOT CONTEXT:
    A screenshot of the user's current screen MAY be provided. If a screenshot path is included, this is what they're looking at RIGHT NOW.
    - Analyze it carefully to understand what app is open, what state it's in, and where UI elements are.
    - Reference specific buttons, menus, tabs, and text visible in the screenshot.
    - If they ask "where is X", find X in the screenshot and point at it.
    - If X isn't visible, explain what they need to do to find it.
    - If NO screenshot is available, still help using general knowledge. Do NOT ask them to take a screenshot.

    """

    func getSystemPrompt() -> String { systemPrompt }

    init(timeoutSeconds: Double = 300) {
        let status = CLIStatus.bestAvailable()
        self.cliPath = status?.path ?? "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/claude"
        self.backend = status?.backend ?? .claude
        self.timeoutSeconds = timeoutSeconds
    }

    func execute(
        userRequest: String,
        screenshotPath: String? = nil,
        screenshotWidth: Int = 0,
        screenshotHeight: Int = 0,
        conversationContext: String? = nil
    ) async throws -> ClaudeCLIResult {
        guard FileManager.default.isExecutableFile(atPath: cliPath) else {
            throw AnnaError.claudeCLIFailed(
                "No AI CLI found. Install Claude Code: curl -fsSL https://claude.ai/install.sh | sh"
            )
        }

        let startTime = Date()

        var fullPrompt = ""
        if let context = conversationContext {
            fullPrompt += "Previous conversation:\n\(context)\n\n"
        }
        if let screenshot = screenshotPath {
            fullPrompt += "(A screenshot of the user's current screen has been saved at: \(screenshot). The screenshot is \(screenshotWidth)x\(screenshotHeight) pixels. Origin (0,0) is the top-left corner. When using [POINT:x,y:label], x ranges from 0 to \(screenshotWidth) and y ranges from 0 to \(screenshotHeight). Analyze it for context.)\n\n"
        }
        fullPrompt += userRequest

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)

        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extraPaths = ["\(home)/.local/bin", "/usr/local/bin", "/opt/homebrew/bin"].joined(separator: ":")
        env["PATH"] = "\(extraPaths):\(env["PATH"] ?? "/usr/bin:/bin")"
        env["TERM"] = "dumb"
        process.environment = env
        process.arguments = [
            "-p", fullPrompt,
            "--dangerously-skip-permissions",
            "--system-prompt", systemPrompt,
            "--output-format", "json",
            "--model", "sonnet",
            "--max-turns", "3",
        ]

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
