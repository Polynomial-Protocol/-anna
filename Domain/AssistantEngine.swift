import Foundation

actor AssistantEngine {
    private let audioCaptureService: AudioCaptureService
    private let voiceService: VoiceTranscriptionService
    private let textInsertionService: TextInsertionService
    private let screenCaptureService: ScreenCaptureService
    private let directExecutor: DirectActionExecutor
    private let claudeCLI: ClaudeCLIService

    private var activeMode: CaptureMode?
    private var conversationHistory: [ConversationTurn] = []

    init(
        audioCaptureService: AudioCaptureService,
        voiceService: VoiceTranscriptionService,
        textInsertionService: TextInsertionService,
        screenCaptureService: ScreenCaptureService,
        directExecutor: DirectActionExecutor,
        claudeCLI: ClaudeCLIService
    ) {
        self.audioCaptureService = audioCaptureService
        self.voiceService = voiceService
        self.textInsertionService = textInsertionService
        self.screenCaptureService = screenCaptureService
        self.directExecutor = directExecutor
        self.claudeCLI = claudeCLI
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
                // Capture screenshot for context
                var screenshotPath: String? = nil
                do {
                    let fileURL = try await screenCaptureService.captureToFile()
                    screenshotPath = fileURL.path
                } catch {
                    // Screenshot failed, continue without it
                }

                // Add to conversation history
                conversationHistory.append(ConversationTurn(
                    role: .user,
                    content: request,
                    timestamp: Date()
                ))

                // Build context with history
                let historyContext = buildHistoryContext()

                let result = try await claudeCLI.execute(
                    userRequest: request,
                    screenshotPath: screenshotPath,
                    conversationContext: historyContext
                )

                // Parse pointer coordinates from response
                let pointer = Self.parsePointerCoordinate(from: result.text)

                // Clean the response text (remove POINT markers)
                let cleanText = Self.cleanResponseText(result.text)

                // Add assistant response to history
                conversationHistory.append(ConversationTurn(
                    role: .assistant,
                    content: cleanText,
                    timestamp: Date()
                ))

                // Keep history manageable (last 10 turns)
                if conversationHistory.count > 20 {
                    conversationHistory = Array(conversationHistory.suffix(20))
                }

                let outcome: AutomationOutcome = result.success
                    ? .completed(summary: cleanText, openedURL: nil)
                    : .blocked(summary: cleanText)
                return (transcript.text, outcome, pointer)
            }
        }
    }

    func cancelCapture() async {
        activeMode = nil
        await audioCaptureService.cancelCapture()
    }

    func clearConversation() {
        conversationHistory.removeAll()
    }

    // MARK: - Conversation Context

    private func buildHistoryContext() -> String? {
        guard conversationHistory.count > 1 else { return nil }
        // Include last few turns as context
        let recent = conversationHistory.suffix(6)
        return recent.map { turn in
            "\(turn.role.rawValue.capitalized): \(turn.content)"
        }.joined(separator: "\n")
    }

    // MARK: - Pointer Parsing

    /// Parses [POINT:x,y:label] or [POINT:none] from Claude response text.
    static func parsePointerCoordinate(from text: String) -> PointerCoordinate? {
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

        var label: String? = nil
        if let labelRange = Range(match.range(at: 3), in: text) {
            label = String(text[labelRange])
        }

        return PointerCoordinate(x: CGFloat(x), y: CGFloat(y), label: label)
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
