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
        self.settingsProvider = settingsProvider
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

    // MARK: - Agent Execution (shared by voice and text paths)

    private func executeAgent(request: String, transcript: String) async throws -> (String, AutomationOutcome?, PointerCoordinate?) {
        // Capture screenshot and its actual pixel dimensions
        var screenshotPath: String? = nil
        var screenshotPixelWidth: Int = 0
        var screenshotPixelHeight: Int = 0
        var screenshotUnavailableReason: String? = nil

        do {
            let capture = try await screenCaptureService.captureToFile()
            screenshotPath = capture.url.path
            screenshotPixelWidth = capture.widthPixels
            screenshotPixelHeight = capture.heightPixels
        } catch {
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
                screenshotUnavailableReason = "Screen Recording permission has not been granted yet. Anna just prompted the user to enable it in System Settings > Privacy & Security > Screen Recording. For now, help without visual context."
            } else {
                screenshotUnavailableReason = "Screenshot capture failed unexpectedly. Help without visual context."
            }
        }

        await conversationStore.append(ConversationTurn(
            role: .user, content: request, timestamp: Date()
        ))

        let historyContext = await buildHistoryContext()
        let knowledgeContext = await buildKnowledgeContext(for: request)

        var fullContext = historyContext ?? ""
        if let knowledge = knowledgeContext {
            fullContext += (fullContext.isEmpty ? "" : "\n\n") + knowledge
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
            screenshotHeight: CGFloat(screenshotPixelHeight)
        )
        let cleanText = Self.cleanResponseText(result.text)

        await conversationStore.append(ConversationTurn(
            role: .assistant, content: cleanText, timestamp: Date()
        ))

        await knowledgeStore.addEntry(
            content: "Q: \(request)\nA: \(cleanText)",
            source: .conversation,
            title: String(request.prefix(80))
        )

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

    // MARK: - Pointer Parsing

    /// Parses [POINT:x,y:label] from Claude response text, attaching screenshot dimensions.
    static func parsePointerCoordinate(from text: String, screenshotWidth: CGFloat, screenshotHeight: CGFloat) -> PointerCoordinate? {
        guard screenshotWidth > 0, screenshotHeight > 0 else { return nil }

        let pattern = #"\[POINT:(\d+)\s*,\s*(\d+)(?::([^\]]+))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }

        guard let xRange = Range(match.range(at: 1), in: text),
              let yRange = Range(match.range(at: 2), in: text),
              let x = Double(text[xRange]),
              let y = Double(text[yRange]) else {
            return nil
        }

        // Clamp to valid range
        let clampedX = min(max(CGFloat(x), 0), screenshotWidth)
        let clampedY = min(max(CGFloat(y), 0), screenshotHeight)

        var label: String? = nil
        if let labelRange = Range(match.range(at: 3), in: text) {
            label = String(text[labelRange])
        }

        return PointerCoordinate(
            x: clampedX,
            y: clampedY,
            label: label,
            screenshotWidth: screenshotWidth,
            screenshotHeight: screenshotHeight
        )
    }

    /// Removes [POINT:...] markers from text for display/TTS.
    static func cleanResponseText(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\s*\[POINT:[^\]]*\]\s*"#,
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
