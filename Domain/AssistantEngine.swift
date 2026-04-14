import Foundation
import CoreGraphics

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

    private var activeMode: CaptureMode?

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
        settingsProvider: @escaping () -> AppSettings
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

    private func executeAgent(request: String, transcript: String, isInternal: Bool = false) async throws -> (String, AutomationOutcome?, PointerCoordinate?) {
        // Exclude Anna's own window from screenshot when touring non-Anna apps
        let settings = settingsProvider()
        let hasExternalTourGuide = !settings.activeTourGuideID.isEmpty
        await MainActor.run { screenCaptureService.excludeAnnaWindow = hasExternalTourGuide }

        // Capture screenshot — track both pixel dimensions and display point dimensions
        var screenshotPath: String? = nil
        var screenshotPixelWidth: Int = 0
        var screenshotPixelHeight: Int = 0
        var displayWidthPoints: Int = 0
        var displayHeightPoints: Int = 0
        var screenshotUnavailableReason: String? = nil

        do {
            let capture = try await screenCaptureService.captureToFile()
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

        let historyContext = await buildHistoryContext()
        let knowledgeContext = await buildKnowledgeContext(for: request)
        let tourGuideContext = await buildTourGuideContext()

        var fullContext = historyContext ?? ""
        if let knowledge = knowledgeContext {
            fullContext += (fullContext.isEmpty ? "" : "\n\n") + knowledge
        }
        if let tourGuide = tourGuideContext {
            fullContext += (fullContext.isEmpty ? "" : "\n\n") + tourGuide
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
