import Foundation
import CoreGraphics
import AppKit

actor AssistantEngine {
    private let audioCaptureService: AudioCaptureService
    private let voiceService: VoiceTranscriptionService
    private let textInsertionService: TextInsertionService
    private let screenCaptureService: ScreenCaptureService
    private let directExecutor: DirectActionExecutor
    private let claudeCLI: ClaudeCLIService
    private let conversationStore: ConversationStore
    private let knowledgeStore: KnowledgeStore
    private let tourGuideStore: TourGuideStore
    private let settingsProvider: () -> AppSettings
    private let perception: PerceptionEngine
    private let wikiKB: WikiKnowledgeBase

    private var activeMode: CaptureMode?
    private var lastTutorObservationAt: Date?
    private static let tutorMinInterval: TimeInterval = 3.0
    /// Spec anti-hallucination threshold: skip proactive tips below this.
    private static let confidenceFloor = 40

    init(
        audioCaptureService: AudioCaptureService,
        voiceService: VoiceTranscriptionService,
        textInsertionService: TextInsertionService,
        screenCaptureService: ScreenCaptureService,
        directExecutor: DirectActionExecutor,
        claudeCLI: ClaudeCLIService,
        conversationStore: ConversationStore,
        knowledgeStore: KnowledgeStore,
        tourGuideStore: TourGuideStore,
        settingsProvider: @escaping () -> AppSettings,
        perception: PerceptionEngine,
        wikiKB: WikiKnowledgeBase = .shared
    ) {
        self.audioCaptureService = audioCaptureService
        self.voiceService = voiceService
        self.textInsertionService = textInsertionService
        self.screenCaptureService = screenCaptureService
        self.directExecutor = directExecutor
        self.claudeCLI = claudeCLI
        self.conversationStore = conversationStore
        self.knowledgeStore = knowledgeStore
        self.tourGuideStore = tourGuideStore
        self.settingsProvider = settingsProvider
        self.perception = perception
        self.wikiKB = wikiKB
    }

    // MARK: - Chat Session Management

    func allSessions() async -> [ChatSession] {
        await conversationStore.activeSessions
    }

    @discardableResult
    func conversationStoreNewSession() async -> ChatSession {
        await conversationStore.newSession()
    }

    func selectSession(_ id: UUID) async {
        await conversationStore.selectSession(id)
    }

    func deleteSession(_ id: UUID) async {
        await conversationStore.deleteSession(id)
    }

    func currentSessionTurns() async -> [ConversationTurn] {
        await conversationStore.allTurns()
    }

    func beginCapture(mode: CaptureMode) async throws {
        activeMode = mode
        try await audioCaptureService.beginCapture()
    }

    func finishCapture() async throws -> (String, AutomationOutcome?, PointerCoordinate?) {
        let mode = activeMode ?? .assistantCommand
        activeMode = nil

        let utterance = try await audioCaptureService.finishCapture()
        let transcript = try await voiceService.transcribe(utterance)

        switch mode {
        case .dictation:
            if await Self.isMediaPlaying() {
                return (
                    transcript.text,
                    .completed(summary: "Transcribed (skipped insertion — media is playing).", openedURL: nil),
                    nil
                )
            }
            try await textInsertionService.insertText(transcript.text)
            return (
                transcript.text,
                .completed(summary: "Inserted text into the active input.", openedURL: nil),
                nil
            )

        case .rewriteDictation:
            let rawText = transcript.text
            if rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (rawText, .completed(summary: "Nothing to rewrite.", openedURL: nil), nil)
            }
            let rewritten = try await rewriteText(rawText)
            try await textInsertionService.insertText(rewritten)
            return (
                rawText,
                .completed(summary: "Rewrote and inserted your text.", openedURL: nil),
                nil
            )

        case .assistantCommand:
            let tier = IntentRouter.route(transcript.text)
            switch tier {
            case .direct(let action):
                let outcome = try await directExecutor.execute(action)
                return (transcript.text, outcome, nil)

            case .agent(let request):
                return try await executeAgent(request: request, transcript: transcript.text)
            }
        }
    }

    /// Execute a text command directly (no audio capture or transcription).
    func executeText(_ text: String) async throws -> (String, AutomationOutcome?, PointerCoordinate?) {
        let tier = IntentRouter.route(text)
        switch tier {
        case .direct(let action):
            let outcome = try await directExecutor.execute(action)
            return (text, outcome, nil)

        case .agent(let request):
            return try await executeAgent(request: request, transcript: text)
        }
    }

    /// Execute an internal text command (e.g., tour continuation) — marks user turn as internal so it doesn't show in chat.
    func executeInternalText(_ text: String) async throws -> (String, AutomationOutcome?, PointerCoordinate?) {
        let tier = IntentRouter.route(text)
        switch tier {
        case .direct(let action):
            let outcome = try await directExecutor.execute(action)
            return (text, outcome, nil)

        case .agent(let request):
            return try await executeAgent(request: request, transcript: text, isInternal: true)
        }
    }

    // MARK: - Agent Execution (shared by voice and text paths)

    /// Runs a proactive tutor observation — capture focused window, ask the model to
    /// guide the user's next step based on what it sees and prior conversation history.
    func executeTutorObservation() async throws -> (String, AutomationOutcome?, PointerCoordinate?) {
        // Spec requirement: debounce to a 3s minimum interval so we don't spam the API
        // on every screen pause. Returns a noop outcome if we're inside the cooldown.
        if let last = lastTutorObservationAt, Date().timeIntervalSince(last) < Self.tutorMinInterval {
            return ("", .completed(summary: "", openedURL: nil), nil)
        }
        lastTutorObservationAt = Date()

        // Anti-hallucination: if the wiki's confidence for the frontmost app is
        // below the floor, skip the proactive tip and log a gap instead.
        if let bundleID = await MainActor.run(body: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }) {
            let confidence = await wikiKB.readConfidence(bundleID: bundleID)
            if confidence < Self.confidenceFloor {
                await LearningLoop.shared.recordLowConfidenceSkip(bundleID: bundleID, query: "proactive tip")
                return ("", .completed(summary: "", openedURL: nil), nil)
            }
        }

        let prompt = "[tutor observation] Look at the screen. The user is actively using this app and just paused. Proactively guide them to the next useful step — one short action, like an instructor would. Check prior conversation history so you don't repeat yourself. If there's a specific UI element to interact with, point at it with [POINT:x,y:label]. If nothing meaningful to say, respond with just [POINT:none]."
        let tier = IntentRouter.route(prompt)
        switch tier {
        case .direct(let action):
            let outcome = try await directExecutor.execute(action)
            return (prompt, outcome, nil)
        case .agent(let request):
            return try await executeAgent(request: request, transcript: prompt, isInternal: true, useFocusedWindow: true)
        }
    }

    private func executeAgent(request: String, transcript: String, isInternal: Bool = false, useFocusedWindow: Bool = false) async throws -> (String, AutomationOutcome?, PointerCoordinate?) {
        // Exclude Anna's own window from screenshot when touring non-Anna apps
        let settings = settingsProvider()
        let hasExternalTourGuide = !settings.activeTourGuideID.isEmpty
        await MainActor.run { screenCaptureService.excludeAnnaWindow = hasExternalTourGuide }

        let preferFocusedWindow = useFocusedWindow || settings.focusedWindowCaptureEnabled

        // Capture screenshot — track both pixel dimensions and display point dimensions
        var screenshotPath: String? = nil
        var screenshotPixelWidth: Int = 0
        var screenshotPixelHeight: Int = 0
        var displayWidthPoints: Int = 0
        var displayHeightPoints: Int = 0
        var screenshotUnavailableReason: String? = nil

        do {
            let capture = preferFocusedWindow
                ? try await screenCaptureService.captureFocusedWindowToFile()
                : try await screenCaptureService.captureToFile()
            screenshotPath = capture.url.path
            screenshotPixelWidth = capture.widthPixels
            screenshotPixelHeight = capture.heightPixels
            displayWidthPoints = capture.displayWidthPoints
            displayHeightPoints = capture.displayHeightPoints
        } catch {
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
                screenshotUnavailableReason = "Screen Recording permission has not been granted yet. Anna just prompted the user to enable it in System Settings > Privacy & Security > Screen Recording. For now, help without visual context."
            } else {
                screenshotUnavailableReason = "Screenshot capture failed unexpectedly. Help without visual context."
            }
        }

        await conversationStore.append(ConversationTurn(
            role: .user, content: request, timestamp: Date(), isInternal: isInternal
        ))

        async let historyContextAsync = buildHistoryContext()
        async let knowledgeContextAsync = buildKnowledgeContext(for: request)
        async let tourGuideContextAsync = buildTourGuideContext()
        async let perceptionAsync = buildPerceptionContext()
        let historyContext = await historyContextAsync
        let knowledgeContext = await knowledgeContextAsync
        let tourGuideContext = await tourGuideContextAsync
        let perception = await perceptionAsync   // (wikiBlock, frontmostBundleID, appName, launchCount)

        var fullContext = historyContext ?? ""
        if let knowledge = knowledgeContext {
            fullContext += (fullContext.isEmpty ? "" : "\n\n") + knowledge
        }
        if let tourGuide = tourGuideContext {
            fullContext += (fullContext.isEmpty ? "" : "\n\n") + tourGuide
        }
        if let wikiBlock = perception.wikiBlock {
            fullContext += (fullContext.isEmpty ? "" : "\n\n") + wikiBlock
        }
        if let reason = screenshotUnavailableReason {
            fullContext += (fullContext.isEmpty ? "" : "\n\n") + reason
        }

        let result = try await executeWithBackend(
            request: request,
            screenshotPath: screenshotPath,
            screenshotWidth: screenshotPixelWidth,
            screenshotHeight: screenshotPixelHeight,
            conversationContext: fullContext.isEmpty ? nil : fullContext
        )

        let pointer = Self.parsePointerCoordinate(
            from: result.text,
            screenshotWidth: CGFloat(screenshotPixelWidth),
            screenshotHeight: CGFloat(screenshotPixelHeight),
            displayWidthPoints: CGFloat(displayWidthPoints),
            displayHeightPoints: CGFloat(displayHeightPoints)
        )
        let cleanText = Self.cleanResponseText(result.text)

        await conversationStore.append(ConversationTurn(
            role: .assistant, content: cleanText, timestamp: Date()
        ))

        // Don't save internal turns (tour continuations, system prompts) to the knowledge base.
        // They pollute the KB and trigger false duplicate-detection.
        if !isInternal {
            await knowledgeStore.addEntry(
                content: "Q: \(request)\nA: \(cleanText)",
                source: .conversation,
                title: String(request.prefix(80))
            )

            // Append to the Karpathy-style raw/ session log. Fire-and-forget.
            let log = WikiKnowledgeBase.SessionLog(
                id: UUID(),
                appBundleID: perception.bundleID,
                appName: perception.appName,
                userQuery: request,
                assistantReply: cleanText,
                screenshotWidthPixels: screenshotPixelWidth > 0 ? screenshotPixelWidth : nil,
                screenshotHeightPixels: screenshotPixelHeight > 0 ? screenshotPixelHeight : nil,
                followed: nil,
                timestamp: Date()
            )
            Task.detached(priority: .utility) { [wikiKB] in
                await wikiKB.appendSession(log)
                // Karpathy loop: if ≥5 new raw sessions have stacked up for
                // this app since the last compile, recompile the wiki page.
                if let bid = log.appBundleID, let name = log.appName {
                    await WikiCompiler().compileIfNeeded(bundleID: bid, appName: name)
                }
            }
        }

        let outcome: AutomationOutcome = result.success
            ? .completed(summary: cleanText, openedURL: nil)
            : .blocked(summary: cleanText)
        return (transcript, outcome, pointer)
    }

    // MARK: - Backend Routing

    private func executeWithBackend(
        request: String,
        screenshotPath: String?,
        screenshotWidth: Int,
        screenshotHeight: Int,
        conversationContext: String?
    ) async throws -> ClaudeCLIResult {
        let settings = settingsProvider()
        let provider = AIProvider(rawValue: settings.aiProvider) ?? .anthropic

        if provider.isAPI {
            guard let apiKey = APIKeyStore.load(for: provider), !apiKey.isEmpty else {
                throw AnnaError.claudeCLIFailed(
                    "No API key set for \(provider.rawValue). Add it in Anna Settings \u{2192} AI Backend."
                )
            }
            let apiService = AIAPIService(
                provider: provider,
                apiKey: apiKey,
                systemPrompt: await claudeCLI.getSystemPrompt()
            )
            return try await apiService.execute(
                userRequest: request,
                screenshotPath: screenshotPath,
                screenshotWidth: screenshotWidth,
                screenshotHeight: screenshotHeight,
                conversationContext: conversationContext
            )
        } else {
            return try await claudeCLI.execute(
                userRequest: request,
                screenshotPath: screenshotPath,
                screenshotWidth: screenshotWidth,
                screenshotHeight: screenshotHeight,
                conversationContext: conversationContext
            )
        }
    }

    // MARK: - Rewrite Text

    /// Sends raw transcribed text to the AI backend for rewriting/polishing,
    /// then returns the cleaned-up version for insertion.
    private func rewriteText(_ rawText: String) async throws -> String {
        let rewritePrompt = """
        Rewrite the following spoken text into clean, well-written text. \
        Fix grammar, punctuation, and awkward phrasing. Keep the meaning and tone intact. \
        Do NOT add anything new or change the intent. \
        Return ONLY the rewritten text, nothing else — no quotes, no explanation, no preamble.

        Spoken text: \(rawText)
        """

        let result = try await executeWithBackend(
            request: rewritePrompt,
            screenshotPath: nil,
            screenshotWidth: 0,
            screenshotHeight: 0,
            conversationContext: nil
        )

        let cleaned = result.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^\"|\"$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? rawText : cleaned
    }

    func cancelCapture() async {
        activeMode = nil
        await audioCaptureService.cancelCapture()
    }

    func clearConversation() async {
        await conversationStore.clear()
    }

    // MARK: - Learning-loop hooks (call from UI buttons)

    /// Called when the user visibly followed the tip (continued the task).
    func recordTipFollowed() async {
        guard let bid = await MainActor.run(body: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }) else { return }
        await LearningLoop.shared.recordSuccess(bundleID: bid)
    }

    /// Called when the user dismissed the tip ("Not now" / close).
    func recordTipDismissed(context: String) async {
        guard let bid = await MainActor.run(body: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }) else { return }
        await LearningLoop.shared.recordDismissal(bundleID: bid, context: context)
    }

    /// Force a wiki recompile for the frontmost app — useful from a debug menu.
    func recompileFrontmostAppWiki() async {
        let info: (String, String)? = await MainActor.run {
            guard let app = NSWorkspace.shared.frontmostApplication,
                  let bid = app.bundleIdentifier else { return nil }
            return (bid, app.localizedName ?? bid)
        }
        guard let (bid, name) = info else { return }
        await WikiCompiler().compileIfNeeded(bundleID: bid, appName: name, force: true)
    }

    // MARK: - Conversation Context

    private func buildHistoryContext() async -> String? {
        let recent = await conversationStore.recentTurns(6)
        guard recent.count > 1 else { return nil }
        return recent.map { turn in
            "\(turn.role.rawValue.capitalized): \(turn.content)"
        }.joined(separator: "\n")
    }

    // MARK: - Knowledge Context

    private func buildKnowledgeContext(for query: String) async -> String? {
        let relevant = await knowledgeStore.findRelevant(query: query, limit: 3)
        guard !relevant.isEmpty else { return nil }

        let entries = relevant.map { "- \($0.title): \($0.content.prefix(200))" }.joined(separator: "\n")
        return "Relevant memories from the user's knowledge base:\n\(entries)"
    }

    // MARK: - Perception Context

    private struct PerceptionContext {
        let wikiBlock: String?
        let bundleID: String?
        let appName: String?
        let launchCount: Int
        let confidence: Int
    }

    private func buildPerceptionContext() async -> PerceptionContext {
        // Snapshot the frontmost app (main-actor bound).
        let snapshot: PerceptionEngine.Snapshot? = await MainActor.run { perception.snapshotFrontmost() }
        guard let snap = snapshot else {
            return PerceptionContext(wikiBlock: nil, bundleID: nil, appName: nil, launchCount: 0, confidence: 50)
        }

        let confidence = await wikiKB.readConfidence(bundleID: snap.app.bundleID)
        let kb = await wikiKB.query(appBundleID: snap.app.bundleID, appName: snap.app.name)

        var lines: [String] = []
        lines.append("FRONTMOST APP: \(snap.app.name) [\(snap.app.bundleID)] — launchCount=\(snap.app.launchCount), confidence=\(confidence), electron=\(snap.app.isElectron)")

        if snap.app.launchCount == 1 {
            lines.append("This is the user's FIRST launch of this app — favor a brief first-time orientation over generic help.")
        }

        if kb.exists, let page = kb.articles.first {
            // Wiki pages may be long; pass the first ~1800 chars to keep prompt tight.
            let trimmed = page.count > 1800 ? String(page.prefix(1800)) + "\n…(truncated)" : page
            lines.append("WIKI/APPS/\(snap.app.bundleID):\n\(trimmed)")
        } else if confidence < Self.confidenceFloor {
            lines.append("No compiled wiki yet for this app and confidence is low — answer conservatively; if you don't know, say so rather than guessing.")
        }

        if !kb.gaps.isEmpty {
            lines.append("Recent open gaps for this app (avoid repeating failures):\n" + kb.gaps.joined(separator: "\n"))
        }

        // Only include the AX tree if it has content — keeps token cost down.
        if !snap.compactJSON.isEmpty && snap.compactJSON != "{}" {
            lines.append("ACCESSIBILITY TREE (\(snap.sizeBytes)B):\n\(snap.compactJSON)")
        }

        return PerceptionContext(
            wikiBlock: lines.joined(separator: "\n\n"),
            bundleID: snap.app.bundleID,
            appName: snap.app.name,
            launchCount: snap.app.launchCount,
            confidence: confidence
        )
    }

    // MARK: - Tour Guide Context

    private func buildTourGuideContext() async -> String? {
        let settings = settingsProvider()

        // If a tour guide is active, inject its content
        if !settings.activeTourGuideID.isEmpty,
           let guide = await tourGuideStore.guideByID(settings.activeTourGuideID),
           let content = await tourGuideStore.loadContent(for: guide) {
            return """
            ACTIVE TOUR GUIDE — "\(guide.displayName)":
            Use this knowledge base to guide the user through the app visible on screen. CRITICAL: Do ONE step per response. Say 1-2 short sentences about what's on screen, then end with [CLICK:x,y:label]. After each click, a new screenshot will arrive and you continue. Never dump all steps at once. No filler words. Keep it natural.

            \(content)
            """
        }

        // No external tour guide active — include Anna's own knowledge base so she can answer questions about herself
        return AnnaKnowledgeBase.appGuide
    }

    // MARK: - Pointer Parsing

    /// Parses [POINT:x,y:label] from Claude response text, attaching screenshot dimensions.
    static func parsePointerCoordinate(from text: String, screenshotWidth: CGFloat, screenshotHeight: CGFloat, displayWidthPoints: CGFloat, displayHeightPoints: CGFloat) -> PointerCoordinate? {
        guard screenshotWidth > 0, screenshotHeight > 0 else { return nil }

        // Match both [POINT:x,y:label] and [CLICK:x,y:label]
        let pattern = #"\[(POINT|CLICK):(\d+)\s*,\s*(\d+)(?::([^\]]+))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }

        guard let actionRange = Range(match.range(at: 1), in: text),
              let xRange = Range(match.range(at: 2), in: text),
              let yRange = Range(match.range(at: 3), in: text),
              let x = Double(text[xRange]),
              let y = Double(text[yRange]) else {
            return nil
        }

        let action: PointerAction = text[actionRange] == "CLICK" ? .click : .point

        let clampedX = min(max(CGFloat(x), 0), screenshotWidth)
        let clampedY = min(max(CGFloat(y), 0), screenshotHeight)

        var label: String? = nil
        if let labelRange = Range(match.range(at: 4), in: text) {
            label = String(text[labelRange])
        }

        return PointerCoordinate(
            x: clampedX,
            y: clampedY,
            label: label,
            action: action,
            screenshotWidth: screenshotWidth,
            screenshotHeight: screenshotHeight,
            displayWidthPoints: displayWidthPoints > 0 ? displayWidthPoints : screenshotWidth,
            displayHeightPoints: displayHeightPoints > 0 ? displayHeightPoints : screenshotHeight
        )
    }

    /// Removes [POINT:...] and [CLICK:...] markers from text for display/TTS.
    static func cleanResponseText(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\s*\[(POINT|CLICK):[^\]]*\]\s*"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Media Playback Detection

    private static func isMediaPlaying() async -> Bool {
        typealias MRNowPlayingInfoCallback = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void

        guard let bundle = CFBundleCreate(kCFAllocatorDefault,
            NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")),
              let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString)
        else {
            return false
        }

        let getNowPlayingInfo = unsafeBitCast(ptr, to: MRNowPlayingInfoCallback.self)

        return await withCheckedContinuation { continuation in
            getNowPlayingInfo(DispatchQueue.main) { info in
                if let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double, rate > 0 {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
