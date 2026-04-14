import SwiftUI
import Combine
import AppKit

@MainActor
final class AssistantViewModel: ObservableObject {
    @Published var events: [AssistantEvent] = []
    @Published var lastTranscript: String = ""
    @Published var lastTranscriptTime: Date? = nil
    @Published var lastResponseTime: Date? = nil
    @Published var statusLine: String = "I'm right here — hold Right ⌘ to talk."
    @Published var isCapturing: Bool = false
    @Published var activeMode: CaptureMode = .assistantCommand
    @Published var status: AnnaStatus = .idle
    @Published var streamingText: String = ""

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm:ss a"
        return f
    }()

    let engine: AssistantEngine
    private let permissionService: PermissionService
    private let ttsService: TTSService
    private let pointerOverlayManager: PointerOverlayManager
    private let settingsProvider: () -> AppSettings
    private let settingsUpdater: (AppSettings) -> Void
    var logger: RuntimeLogger?
    /// Injected by `AppContainer` so typed walkthrough requests can bypass
    /// the agent and open the stepper panel directly. Optional so tests /
    /// lightweight contexts can skip it.
    weak var walkthroughController: WalkthroughController?
    var tourAnalytics: TourAnalytics { TourAnalytics(logger: logger) }

    private var recorderReady = false
    private var pendingEnd = false
    private var tourStartTime: Date?

    // Tutor mode (idle-triggered proactive observations)
    private let idleDetector = UserActivityIdleDetector()
    private var idleCancellable: AnyCancellable?
    private var isTutorObservationInFlight = false

    init(
        engine: AssistantEngine,
        permissionService: PermissionService,
        ttsService: TTSService,
        pointerOverlayManager: PointerOverlayManager,
        settingsProvider: @escaping () -> AppSettings,
        settingsUpdater: @escaping (AppSettings) -> Void
    ) {
        self.engine = engine
        self.permissionService = permissionService
        self.ttsService = ttsService
        self.pointerOverlayManager = pointerOverlayManager
        self.settingsProvider = settingsProvider
        self.settingsUpdater = settingsUpdater

        // Idle detector runs continuously — the trigger handler gates on the setting.
        idleDetector.start()
        idleCancellable = idleDetector.$isUserIdle
            .filter { $0 == true }
            .sink { [weak self] _ in
                self?.handleIdleTrigger()
            }
    }

    // MARK: - Tutor Mode

    private func handleIdleTrigger() {
        // Guards: no overlap with any active user-driven flow.
        guard settingsProvider().tutorModeEnabled,
              !isCapturing,
              status == .idle,
              !ttsService.isSpeaking,
              !isInTourMode,
              !isTutorObservationInFlight else { return }

        isTutorObservationInFlight = true
        status = .thinking
        statusLine = "Taking a look..."
        logger?.log("Tutor idle trigger — running observation", tag: "tutor")

        Task {
            defer {
                self.idleDetector.observationDidComplete()
                self.isTutorObservationInFlight = false
            }
            do {
                let result = try await engine.executeTutorObservation()
                await MainActor.run {
                    guard let outcome = result.1 else {
                        self.status = .idle
                        self.statusLine = "I'm right here — hold Right ⌘ to talk."
                        return
                    }
                    let responseText: String
                    switch outcome {
                    case .completed(let summary, _): responseText = summary
                    case .needsConfirmation(let summary): responseText = summary
                    case .blocked(let summary): responseText = summary
                    }
                    // Skip pure [POINT:none] "nothing to say" observations silently.
                    let trimmed = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        self.status = .idle
                        self.statusLine = "I'm right here — hold Right ⌘ to talk."
                        return
                    }
                    self.lastResponseTime = Date()
                    let cleanText = self.ingestPlanFromResponse(responseText)
                    self.animateStreamingText(cleanText)
                    self.copyResponseIfEnabled(cleanText)
                    // Tutor observations must NOT start a guided walkthrough —
                    // pass standalone: true so handlePointerAndSpeak only
                    // renders the pointer + TTS and then exits.
                    self.handlePointerAndSpeak(pointer: result.2, responseText: cleanText, standalone: true)
                }
            } catch {
                await MainActor.run {
                    self.status = .idle
                    self.statusLine = "I'm right here — hold Right ⌘ to talk."
                    self.logger?.log("Tutor observation error: \(error.localizedDescription)", tag: "tutor")
                }
            }
        }
    }

    // MARK: - Auto-copy

    private func copyResponseIfEnabled(_ text: String) {
        guard settingsProvider().autoCopyResponsesEnabled else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(clean, forType: .string)
    }

    /// Whether Anna paused media when starting capture — so we know whether to resume afterward.
    private var didPauseMedia = false

    func beginCapture(mode: CaptureMode) {
        // Interrupt any current activity: stop TTS, cancel in-flight tour continuations
        if ttsService.isSpeaking {
            ttsService.stop()
            logger?.log("Interrupted TTS — user pressed hotkey", tag: "interrupt")
        }
        if isInTourMode {
            // User is interjecting mid-tour — stop the tour so this new command is standalone
            isInTourMode = false
            guidedModeStepCount = 0
            logger?.log("Interrupted tour — user pressed hotkey", tag: "interrupt")
        }

        guard !isCapturing else { return }
        isCapturing = true
        activeMode = mode
        recorderReady = false
        pendingEnd = false
        status = .listening
        streamingText = ""
        switch mode {
        case .assistantCommand: statusLine = "I'm listening..."
        case .dictation: statusLine = "Go ahead, I'll type it out..."
        case .rewriteDictation: statusLine = "Speak freely — I'll clean it up after..."
        }
        logger?.log("Begin capture — mode: \(mode.rawValue)", tag: "capture")

        // Pause any media playing so mic capture isn't contaminated
        Task {
            let paused = await MediaController.pauseIfPlaying()
            await MainActor.run {
                self.didPauseMedia = paused
                if paused { self.logger?.log("Paused media for capture", tag: "media") }
            }
        }

        Task {
            do {
                try await engine.beginCapture(mode: mode)
                await MainActor.run {
                    self.logger?.log("Audio capture started successfully", tag: "capture")
                    self.recorderReady = true
                    if self.pendingEnd {
                        self.pendingEnd = false
                        self.doEndCapture()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isCapturing = false
                    self.recorderReady = false
                    self.status = .idle
                    let errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.logger?.log("Capture failed: \(errorMsg)", tag: "capture")
                    self.pushEvent(title: "Capture failed", body: errorMsg, tone: .failure)
                }
            }
        }
    }

    func endCapture() {
        guard isCapturing else { return }

        if recorderReady {
            doEndCapture()
        } else {
            logger?.log("Key released before recorder ready — queueing end", tag: "capture")
            pendingEnd = true
        }
    }

    private func doEndCapture() {
        status = .thinking
        logger?.log("End capture — transcribing...", tag: "capture")
        Task {
            do {
                let result = try await engine.finishCapture()
                await MainActor.run {
                    self.isCapturing = false
                    self.recorderReady = false
                    self.lastTranscript = result.0
                    self.lastTranscriptTime = Date()
                    // Every new user request starts a fresh task. Task mode stays on until
                    // the model emits [POINT:none] (done marker) or the safety cap trips.
                    self.isInTourMode = true
                    self.guidedModeStepCount = 0
                    self.tourStartTime = Date()
                    self.tourOriginalRequest = result.0
                    self.taskIntent = Self.detectIntent(from: result.0)
                    self.teachSamePointerStreak = 0
                    self.lastTeachPointerKey = ""
                    self.cachedPlan = ""
                    self.cachedPlanStepCount = 0
                    self.continuationFailures = 0
                    let settings = self.settingsProvider()
                    self.tourAnalytics.tourStarted(tourGuideID: settings.activeTourGuideID, tourName: "Voice task")
                    self.logger?.log("Transcription: \"\(result.0)\" (intent: \(self.taskIntent))", tag: "voice")

                    if let outcome = result.1 {
                        let responseText: String
                        switch outcome {
                        case .completed(let summary, let url):
                            responseText = summary
                            self.logger?.log("Action completed: \(summary) \(url?.absoluteString ?? "")", tag: "action")
                            self.pushEvent(title: "Action completed", body: "\(result.0)\n\n\(summary)", tone: .success)
                        case .needsConfirmation(let summary):
                            responseText = summary
                            self.logger?.log("Action needs confirmation: \(summary)", tag: "action")
                            self.pushEvent(title: "Needs confirmation", body: "\(result.0)\n\n\(summary)", tone: .warning)
                        case .blocked(let summary):
                            responseText = summary
                            self.logger?.log("Action blocked: \(summary)", tag: "action")
                            self.pushEvent(title: "Action blocked", body: "\(result.0)\n\n\(summary)", tone: .failure)
                        }

                        // Record response time and show streaming text effect
                        self.lastResponseTime = Date()
                        let cleanText = self.ingestPlanFromResponse(responseText)
                        self.animateStreamingText(cleanText)
                        self.copyResponseIfEnabled(cleanText)

                        // Handle pointer/click and TTS
                        self.handlePointerAndSpeak(pointer: result.2, responseText: cleanText)
                    } else {
                        self.status = .idle
                        self.statusLine = "All done — I'm here if you need me."
                    }
                }
            } catch {
                await MainActor.run {
                    self.isCapturing = false
                    self.recorderReady = false
                    self.status = .idle
                    self.statusLine = "Hmm, something went wrong. Try again?"
                    let errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.logger?.log("Action failed: \(errorMsg)", tag: "action")
                    self.pushEvent(title: "Action failed", body: errorMsg, tone: .failure)
                }
            }
        }
    }

    // MARK: - Streaming Text Animation

    private func animateStreamingText(_ fullText: String) {
        streamingText = ""
        let words = fullText.split(separator: " ")
        for (index, word) in words.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.04) {
                if index == 0 {
                    self.streamingText = String(word)
                } else {
                    self.streamingText += " " + String(word)
                }
            }
        }
    }

    /// Send a typed text command directly to the engine (no audio capture).
    func sendText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isCapturing else { return }

        // Walkthrough intent: "show me how to X", "walk me through X",
        // "teach me X", "guide me through X" → route to stepper instead
        // of the agent, so the user gets a real sequenced plan.
        if let task = Self.extractWalkthroughTask(from: trimmed),
           let walkthrough = walkthroughController {
            let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "this app"
            logger?.log("Walkthrough intent: \"\(task)\" in \(appName)", tag: "walkthrough")
            walkthrough.start(task: task, appName: appName)
            return
        }

        isCapturing = true
        status = .thinking
        streamingText = ""
        statusLine = "Thinking..."
        logger?.log("Text input: \"\(trimmed)\"", tag: "text")

        Task {
            do {
                let result = try await engine.executeText(trimmed)
                await MainActor.run {
                    self.isCapturing = false
                    self.lastTranscript = result.0
                    self.lastTranscriptTime = Date()
                    // Fresh text input starts a new task.
                    self.isInTourMode = true
                    self.guidedModeStepCount = 0
                    self.tourStartTime = Date()
                    self.tourOriginalRequest = trimmed
                    self.taskIntent = Self.detectIntent(from: trimmed)
                    self.teachSamePointerStreak = 0
                    self.lastTeachPointerKey = ""
                    self.cachedPlan = ""
                    self.cachedPlanStepCount = 0
                    self.continuationFailures = 0
                    let settings = self.settingsProvider()
                    self.tourAnalytics.tourStarted(tourGuideID: settings.activeTourGuideID, tourName: "Text task")
                    self.logger?.log("Text result: \"\(result.0)\" (intent: \(self.taskIntent))", tag: "text")

                    if let outcome = result.1 {
                        let responseText: String
                        switch outcome {
                        case .completed(let summary, let url):
                            responseText = summary
                            self.logger?.log("Action completed: \(summary) \(url?.absoluteString ?? "")", tag: "action")
                            self.pushEvent(title: "Action completed", body: "\(result.0)\n\n\(summary)", tone: .success)
                        case .needsConfirmation(let summary):
                            responseText = summary
                            self.pushEvent(title: "Needs confirmation", body: "\(result.0)\n\n\(summary)", tone: .warning)
                        case .blocked(let summary):
                            responseText = summary
                            self.pushEvent(title: "Action blocked", body: "\(result.0)\n\n\(summary)", tone: .failure)
                        }

                        self.lastResponseTime = Date()
                        self.animateStreamingText(responseText)

                        self.handlePointerAndSpeak(pointer: result.2, responseText: responseText)
                    } else {
                        self.status = .idle
                        self.statusLine = "All done — I'm here if you need me."
                    }
                }
            } catch {
                await MainActor.run {
                    self.isCapturing = false
                    self.status = .idle
                    self.statusLine = "Hmm, something went wrong. Try again?"
                    let errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.logger?.log("Text action failed: \(errorMsg)", tag: "action")
                    self.pushEvent(title: "Action failed", body: errorMsg, tone: .failure)
                }
            }
        }
    }

    // MARK: - Pointer, Click & Guided Mode

    private var guidedModeStepCount = 0
    /// Hard safety cap against infinite loops — matches the conversation session turn limit (100 turns ≈ 50 steps).
    /// In practice Claude ends tours via [POINT:none] well before hitting this.
    private let maxGuidedSteps = 50

    /// True if we should fire another walkthrough continuation. Honors the
    /// planned step count when we have one; falls back to the 50-step
    /// safety cap for unplanned (reactive) tours.
    private func shouldContinueGuidedStep() -> Bool {
        if self.cachedPlanStepCount > 0 {
            return self.guidedModeStepCount < self.cachedPlanStepCount
        }
        return self.guidedModeStepCount < self.maxGuidedSteps
    }
    @Published var isInTourMode = false
    /// Stores the user's original tour request so continuation prompts can preserve the user's intent (basic vs complete).
    private var tourOriginalRequest: String = ""

    /// Plan emitted by the model on turn 1 as "[PLAN: step1 → step2 → step3]", cached so every
    /// continuation can remind the model of the full sequence and stop re-planning.
    private var cachedPlan: String = ""
    private var cachedPlanStepCount: Int = 0
    /// How many times a continuation has failed in this task; limits noisy retry loops.
    private var continuationFailures: Int = 0
    /// Parses and strips a "[PLAN: ...]" line from a model response.
    /// Returns the plan text (without brackets) and the cleaned response.
    /// Ingests a response from the model: pulls out a [PLAN: ...] line if present (caching it
    /// for later continuations) and returns the cleaned text to speak/display.
    private func ingestPlanFromResponse(_ text: String) -> String {
        let parsed = Self.extractPlan(from: text)
        if !parsed.plan.isEmpty && self.cachedPlan.isEmpty {
            self.cachedPlan = parsed.plan
            self.cachedPlanStepCount = max(parsed.stepCount, 1)
            self.logger?.log("Cached plan (\(self.cachedPlanStepCount) steps): \(parsed.plan)", tag: "guide")
        }
        return parsed.cleaned
    }

    private static func extractPlan(from text: String) -> (plan: String, stepCount: Int, cleaned: String) {
        let regex = try? NSRegularExpression(pattern: #"\[PLAN:\s*([^\]]+)\]"#, options: [.caseInsensitive])
        guard let regex else { return ("", 0, text) }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let planRange = Range(match.range(at: 1), in: text),
              let fullRange = Range(match.range, in: text) else {
            return ("", 0, text)
        }
        let planText = String(text[planRange]).trimmingCharacters(in: .whitespaces)
        let stepCount = planText
            .components(separatedBy: CharacterSet(charactersIn: "→>,;·•|"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .count
        var cleaned = text
        cleaned.removeSubrange(fullRange)
        return (planText, stepCount, cleaned.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Whether the current task is user wanting Anna to *do* it, or asking Anna to *teach* them how.
    /// Preserved across continuation turns so the whole task stays in one mode.
    enum TaskIntent { case doIt, teach }
    private var taskIntent: TaskIntent = .doIt
    /// Counts consecutive same-coordinate pointers in teach mode — if the user doesn't move
    /// after 3 attempts at the same spot, we bail out instead of re-pointing forever.
    private var teachSamePointerStreak: Int = 0
    private var lastTeachPointerKey: String = ""

    private static let teachPhrases: [String] = [
        "how do i", "how to", "how can i", "how should i",
        "show me how", "show me where", "show me the",
        "teach me", "guide me", "walk me through",
        "where is", "where's", "where do i", "where can i",
        "tell me how", "explain how", "help me find"
    ]

    /// Client-side intent heuristic. The system prompt also enforces this model-side
    /// so obvious miscalls are corrected. Ambiguous inputs default to `.teach` (safer —
    /// user can always say "just do it").
    static func detectIntent(from text: String) -> TaskIntent {
        let lower = text.lowercased()
        if teachPhrases.contains(where: { lower.contains($0) }) { return .teach }
        if lower.contains("?") && !lower.hasPrefix("can you ") && !lower.hasPrefix("could you ") {
            // Questions default to teach, except "can you do X?" which is a polite command.
            return .teach
        }
        return .doIt
    }

    /// Detects the end-of-task marker. [POINT:none] is the canonical done signal;
    /// [DONE] is also accepted for models that find it more natural.
    private static func isTourEndMarker(_ text: String) -> Bool {
        if text.range(of: #"\[POINT:\s*none\s*\]"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"\[DONE\]"#, options: .regularExpression) != nil { return true }
        return false
    }

    private func handlePointerAndSpeak(pointer: PointerCoordinate?, responseText: String, standalone: Bool = false) {
        let isClick = pointer?.action == .click
        let clickLocation = isClick ? pointer.flatMap { PointerOverlayManager.screenLocation(for: $0) } : nil
        let isTourEnd = Self.isTourEndMarker(responseText)

        // Step 1: Ensure overlay is visible when we have something to show
        if pointer != nil && !self.pointerOverlayManager.isVisible {
            self.pointerOverlayManager.showOverlay(viewModel: self)
        }

        // Step 2: Fly buddy to target
        if let pointer = pointer {
            self.pointerOverlayManager.pointAt(pointer)
        }

        // Step 3: Speak, then sequence click and continuation AFTER speech ends
        let settings = self.settingsProvider()
        if settings.ttsEnabled {
            self.status = .speaking
            self.ttsService.speak(responseText, rate: settings.ttsRate, voiceIdentifier: settings.ttsVoiceIdentifier, engine: settings.ttsEngine, elevenLabsVoiceID: settings.elevenLabsVoiceID)
        }

        Task {
            // Wait for TTS to finish before doing anything else
            if settings.ttsEnabled {
                while self.ttsService.isSpeaking {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }

            await MainActor.run {
                if isTourEnd {
                    // Model decided the task is done — trust its judgment.
                    self.finishTour()
                    return
                }

                // STANDALONE calls (tutor idle observation, first-launch tip, etc.)
                // must not drive a guided walkthrough — they're one-shot hints.
                // Render pointer + speech, then exit without entering any
                // waitForUserAndContinue / continueGuidedWalkthrough loop.
                if standalone {
                    self.status = .idle
                    self.statusLine = "I'm right here — hold Right ⌘ to talk."
                    return
                }

                // TEACH intent: never click. Point, then wait for the user to do it themselves.
                if self.taskIntent == .teach && pointer != nil {
                    let key = "\(pointer!.x),\(pointer!.y)"
                    if key == self.lastTeachPointerKey {
                        self.teachSamePointerStreak += 1
                    } else {
                        self.teachSamePointerStreak = 1
                        self.lastTeachPointerKey = key
                    }

                    if self.teachSamePointerStreak >= 3 {
                        self.logger?.log("Teach mode: 3× same pointer with no user action — bailing", tag: "guide")
                        self.statusLine = "Hmm, looks stuck. Tell me if you'd like me to do it for you."
                        self.status = .idle
                        return
                    }

                    self.guidedModeStepCount += 1
                    self.statusLine = "Your turn — click the highlighted spot."
                    self.status = .idle
                    self.logger?.log("Teach step \(self.guidedModeStepCount) — waiting for user action at \(key)", tag: "guide")

                    // Wait until the user has been idle for a beat (i.e. they did something and paused),
                    // then advance. Safety cap: give up after 60s of inactivity.
                    if self.shouldContinueGuidedStep() {
                        self.waitForUserAndContinue()
                    } else {
                        self.logger?.log("Plan complete — finishing tour after last step", tag: "guide")
                        self.finishTour()
                    }
                    return
                }

                // DO intent + CLICK — execute ourselves, then continue.
                if isClick, let loc = clickLocation {
                    self.pointerOverlayManager.clickRippleAt = loc
                    ClickSimulator.click(at: loc)
                    self.logger?.log("Guided click at (\(Int(loc.x)), \(Int(loc.y))): \(pointer?.label ?? "element")", tag: "guide")
                    self.tourAnalytics.stepClicked(stepIndex: self.guidedModeStepCount, clickTarget: pointer?.label, durationMs: 0)

                    self.guidedModeStepCount += 1
                    self.statusLine = "Working on it... step \(self.guidedModeStepCount + 1)"
                    if self.shouldContinueGuidedStep() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            self.continueGuidedWalkthrough()
                        }
                    } else {
                        self.logger?.log("Plan complete — finishing tour after last step", tag: "guide")
                        self.finishTour()
                    }
                    return
                }

                // DO intent + POINT mid-task (model chose to just indicate something, not click).
                if pointer != nil && self.isInTourMode {
                    self.guidedModeStepCount += 1
                    if self.shouldContinueGuidedStep() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            self.continueGuidedWalkthrough()
                        }
                    } else {
                        self.logger?.log("Plan complete — finishing tour after last step", tag: "guide")
                        self.finishTour()
                    }
                    return
                }

                // No click, no pointer — single-turn answer (e.g. "it's 3pm"). Task ends naturally.
                self.pointerOverlayManager.hide()
                self.isInTourMode = false
                self.guidedModeStepCount = 0
                self.status = .idle
                self.statusLine = "All done — I'm here if you need me."
            }
        }
    }

    private func finishTour(logCompletion: Bool = true) {
        if logCompletion {
            let totalMs = Int((Date().timeIntervalSince(tourStartTime ?? Date())) * 1000)
            tourAnalytics.tourCompleted(totalSteps: guidedModeStepCount, totalDurationMs: totalMs)
        }
        self.guidedModeStepCount = 0
        self.isInTourMode = false
        self.tourStartTime = nil
        self.pointerOverlayManager.hide()
        self.status = .idle
        self.statusLine = "All done — I'm here if you need me."
        self.logger?.log("Guided tour finished", tag: "guide")
    }

    /// Teach mode: as soon as the user clicks and pauses briefly (~800ms), advance.
    /// Bails after 60s if they don't click at all.
    private func waitForUserAndContinue() {
        let taskAtSchedule = self.tourStartTime
        let quiescenceThreshold: TimeInterval = 0.8  // fast: advance 0.8s after their last click
        let maxWait: TimeInterval = 60

        // Clear any stale click marker so we only match a NEW click after this step began.
        idleDetector.resetClickMarker()

        Task {
            let startedAt = Date()
            while Date().timeIntervalSince(startedAt) < maxWait {
                if self.tourStartTime != taskAtSchedule { return }

                let sinceInput = self.idleDetector.secondsSinceLastInput
                let lastClick = self.idleDetector.lastClickTimestamp
                let hasClicked = lastClick != nil

                // Advance when: they've clicked at least once since we started waiting,
                // they've been quiet for ≥ threshold, and we're not already busy.
                if hasClicked,
                   sinceInput >= quiescenceThreshold,
                   !self.isCapturing,
                   !self.ttsService.isSpeaking {
                    await MainActor.run {
                        self.logger?.log("Teach step: click detected + \(String(format: "%.1f", sinceInput))s quiet — advancing", tag: "guide")
                        self.idleDetector.observationDidComplete()
                        self.continueGuidedWalkthrough()
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 150_000_000)  // poll every 150ms for responsiveness
            }
            await MainActor.run {
                guard self.tourStartTime == taskAtSchedule else { return }
                self.logger?.log("Teach mode: 60s no click — ending task", tag: "guide")
                self.finishTour()
            }
        }
    }

    private func continueGuidedWalkthrough() {
        guard !isCapturing else { return }
        self.status = .thinking

        let stepNum = self.guidedModeStepCount + 1
        let progressSuffix: String
        if self.cachedPlanStepCount > 0 {
            let clamped = min(stepNum, self.cachedPlanStepCount)
            progressSuffix = "step \(clamped) of \(self.cachedPlanStepCount)"
        } else {
            progressSuffix = "step \(stepNum)"
        }

        if self.taskIntent == .teach {
            self.statusLine = "\(progressSuffix.capitalized) — your turn"
        } else {
            self.statusLine = "Working on \(progressSuffix)..."
        }
        self.logger?.log("Continuing walkthrough (\(progressSuffix), plan: '\(self.cachedPlan)')", tag: "guide")

        // Ensure overlay is visible for the next pointer
        if !self.pointerOverlayManager.isVisible {
            self.pointerOverlayManager.showOverlay(viewModel: self)
        }

        Task {
            do {
                let originalRequest = self.tourOriginalRequest.isEmpty ? "their previous request" : "\"\(self.tourOriginalRequest)\""
                let planBlock: String = self.cachedPlan.isEmpty
                    ? ""
                    : "YOUR PLAN (made on step 1): \(self.cachedPlan). You are now at step \(stepNum). Stick to the plan. Do NOT re-plan. "

                let prompt: String
                switch self.taskIntent {
                case .teach:
                    prompt = "\(planBlock)TEACHING the user. Original ask: \(originalRequest). Look at the NEW screenshot. Did they advance past the previous step? YES → next step from the plan in ONE short sentence (max 8 words) + [POINT:x,y:label]. NO → re-point same spot, ONE short line. Goal reached → 'nice, got it' + [POINT:none]. NEVER use [CLICK:...]. Be EXTREMELY brief — every word costs the user time."
                case .doIt:
                    prompt = "\(planBlock)Continuing the user's task. Original ask: \(originalRequest). Look at the NEW screenshot. Is the original goal satisfied now? YES → short closing line + [POINT:none]. NO → do the next step from the plan: 1 short sentence + [CLICK:x,y:label]. If the screen looks unchanged from before, the click didn't land — say so briefly and try a slightly different spot. Stay in the currently visible app — do NOT switch apps."
                }
                let result = try await self.executeContinuationWithRetry(prompt: prompt)
                await MainActor.run {
                    self.lastTranscript = "Guided walkthrough (step \(self.guidedModeStepCount + 1))"
                    self.lastTranscriptTime = Date()

                    if let outcome = result.1 {
                        let responseText: String
                        switch outcome {
                        case .completed(let summary, _):
                            responseText = summary
                            self.pushEvent(title: "Guided step", body: summary, tone: .success)
                        case .needsConfirmation(let summary):
                            responseText = summary
                            self.pushEvent(title: "Guided step", body: summary, tone: .warning)
                        case .blocked(let summary):
                            responseText = summary
                            self.pushEvent(title: "Guided step", body: summary, tone: .failure)
                        }

                        self.lastResponseTime = Date()
                        let cleanText = self.ingestPlanFromResponse(responseText)
                        self.animateStreamingText(cleanText)
                        self.copyResponseIfEnabled(cleanText)
                        self.handlePointerAndSpeak(pointer: result.2, responseText: cleanText)
                    } else {
                        self.guidedModeStepCount = 0
                        self.status = .idle
                        self.statusLine = "All done — I'm here if you need me."
                    }
                }
            } catch {
                await MainActor.run {
                    self.logger?.log("Continuation error after retry: \(error.localizedDescription)", tag: "guide")
                    self.ttsService.speak(
                        "Hit a snag. Stopping here.",
                        rate: self.settingsProvider().ttsRate,
                        voiceIdentifier: self.settingsProvider().ttsVoiceIdentifier,
                        engine: self.settingsProvider().ttsEngine,
                        elevenLabsVoiceID: self.settingsProvider().elevenLabsVoiceID
                    )
                    self.finishTour()
                }
            }
        }
    }

    /// Runs a continuation prompt against the engine, retrying once on transient failure
    /// with a short backoff. Throws only if both attempts fail.
    private func executeContinuationWithRetry(prompt: String) async throws -> (String, AutomationOutcome?, PointerCoordinate?) {
        do {
            return try await engine.executeInternalText(prompt)
        } catch {
            self.logger?.log("Continuation attempt 1 failed (\(error.localizedDescription)) — retrying", tag: "guide")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            return try await engine.executeInternalText(prompt)
        }
    }

    func cancelCapture() {
        guard isCapturing else { return }
        logger?.log("Capture cancelled by user", tag: "capture")
        pendingEnd = false
        ttsService.stop()
        Task {
            await engine.cancelCapture()
            await MainActor.run {
                self.isCapturing = false
                self.recorderReady = false
                self.status = .idle
                self.statusLine = "No worries, cancelled."
            }
        }
    }

    func stopSpeaking() {
        ttsService.stop()
        if status == .speaking {
            status = .idle
        }
    }

    func stopTour() {
        ttsService.stop()
        let totalMs = Int((Date().timeIntervalSince(tourStartTime ?? Date())) * 1000)
        tourAnalytics.tourAbandoned(stepIndex: guidedModeStepCount, reason: "user_stopped", totalDurationMs: totalMs)
        finishTour(logCompletion: false)
        logger?.log("Tour stopped by user", tag: "guide")
    }

    func refreshPermissionsSummary() -> String {
        let statuses = permissionService.refresh()
        let readyCount = statuses.filter { $0.state == .granted }.count
        let summary = "\(readyCount)/\(statuses.count) permissions ready"
        logger?.log("Permission check: \(summary)", tag: "permission")
        for s in statuses {
            logger?.log("  \(s.kind.rawValue): \(s.state.rawValue) — \(s.detail)", tag: "permission")
        }
        return summary
    }

    /// Surfaces a proactive tip (e.g. first-launch onboarding) in the response
    /// bubble. Public so `AppActivationObserver` can push first-launch tips
    /// without going through a capture cycle.
    func displayProactiveTip(_ text: String) {
        lastTranscript = ""
        streamingText = text
        lastResponseTime = Date()
        statusLine = text
        pushEvent(title: "Onboarding tip", body: text, tone: .neutral)
    }

    /// Detect a walkthrough intent in a free-form sentence and return the
    /// extracted task, stripped of the triggering phrase. Returns nil when
    /// the sentence is a normal agent command.
    ///
    /// Examples that match:
    ///   "show me how to add a layer mask" → "add a layer mask"
    ///   "walk me through exporting to PDF" → "exporting to PDF"
    ///   "teach me how to set up a pivot table" → "set up a pivot table"
    ///   "guide me through sharing a file" → "sharing a file"
    static func extractWalkthroughTask(from text: String) -> String? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Ordered longest-first so we strip the most specific prefix.
        let triggers = [
            "show me how to ",
            "teach me how to ",
            "walk me through ",
            "guide me through ",
            "teach me to ",
            "teach me ",
            "how do i "
        ]
        for t in triggers where lower.hasPrefix(t) {
            let task = String(text.dropFirst(t.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            // Drop trailing "?" or "."
            let trimmed = task.trimmingCharacters(in: CharacterSet(charactersIn: "?."))
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private func pushEvent(title: String, body: String, tone: AssistantEvent.EventTone) {
        events.insert(
            AssistantEvent(
                id: UUID(),
                timestamp: Date(),
                title: title,
                body: body,
                tone: tone
            ),
            at: 0
        )
    }
}
