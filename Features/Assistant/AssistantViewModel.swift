import SwiftUI

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

    private var recorderReady = false
    private var pendingEnd = false

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
    }

    func beginCapture(mode: CaptureMode) {
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
                    self.isInTourMode = self.detectTourMode(from: result.0)
                    self.guidedModeStepCount = 0
                    self.logger?.log("Transcription: \"\(result.0)\" (tour: \(self.isInTourMode))", tag: "voice")

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
                        self.animateStreamingText(responseText)

                        // Handle pointer/click and TTS
                        self.handlePointerAndSpeak(pointer: result.2, responseText: responseText)
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
                    // Only set tour mode from original user input, not continuation prompts
                    if !self.isInTourMode {
                        self.isInTourMode = self.detectTourMode(from: trimmed)
                        self.guidedModeStepCount = 0
                    }
                    self.logger?.log("Text result: \"\(result.0)\" (tour: \(self.isInTourMode))", tag: "text")

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
    private let maxGuidedSteps = 8
    @Published var isInTourMode = false

    private static let tourKeywords = [
        "tour", "walk me through", "walkthrough", "walk through",
        "show me everything", "show me around", "demo", "guide me",
        "give me a tour", "all the tabs", "all the features",
        "show me all", "explain the app", "explain anna"
    ]

    private func detectTourMode(from text: String) -> Bool {
        let lower = text.lowercased()
        return Self.tourKeywords.contains { lower.contains($0) }
    }

    /// Detects the [POINT:none] end-of-tour marker that doesn't match the coordinate regex.
    private static func isTourEndMarker(_ text: String) -> Bool {
        text.range(of: #"\[POINT:\s*none\s*\]"#, options: .regularExpression) != nil
    }

    private func handlePointerAndSpeak(pointer: PointerCoordinate?, responseText: String) {
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
                if isClick, let loc = clickLocation {
                    // Click AFTER speech finishes
                    self.pointerOverlayManager.clickRippleAt = loc
                    ClickSimulator.click(at: loc)
                    self.logger?.log("Guided click at (\(Int(loc.x)), \(Int(loc.y))): \(pointer?.label ?? "element")", tag: "guide")

                    if self.isInTourMode {
                        // Tour mode: keep overlay, continue after delay
                        self.guidedModeStepCount += 1
                        self.statusLine = "Showing you around... step \(self.guidedModeStepCount + 1)"
                        if self.guidedModeStepCount < self.maxGuidedSteps {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                self.continueGuidedWalkthrough()
                            }
                        } else {
                            self.finishTour()
                        }
                    } else {
                        // One-off click — hide pointer after brief delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            self.pointerOverlayManager.hide()
                        }
                        self.status = .idle
                        self.statusLine = "All done — I'm here if you need me."
                    }

                } else if isTourEnd {
                    // Explicit tour end: [POINT:none]
                    self.finishTour()

                } else if self.isInTourMode {
                    // Mid-tour response without a click (e.g., POINT action or description-only)
                    // Keep tour alive and continue to next step
                    self.guidedModeStepCount += 1
                    if pointer != nil {
                        // Has a POINT — show it briefly, then continue
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            self.continueGuidedWalkthrough()
                        }
                    } else if self.guidedModeStepCount < self.maxGuidedSteps {
                        // No pointer but still in tour — continue
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self.continueGuidedWalkthrough()
                        }
                    } else {
                        self.finishTour()
                    }

                } else {
                    // Not in tour mode, no click — just finish
                    self.pointerOverlayManager.hide()
                    self.status = .idle
                    self.statusLine = "All done — I'm here if you need me."
                }
            }
        }
    }

    private func finishTour() {
        self.guidedModeStepCount = 0
        self.isInTourMode = false
        self.pointerOverlayManager.hide()
        self.status = .idle
        self.statusLine = "All done — I'm here if you need me."
        self.logger?.log("Guided tour completed", tag: "guide")
    }

    private func continueGuidedWalkthrough() {
        guard !isCapturing else { return }
        self.status = .thinking
        self.statusLine = "Showing you around... step \(guidedModeStepCount + 1)"
        self.logger?.log("Guided mode: continuing walkthrough (step \(guidedModeStepCount + 1))", tag: "guide")

        // Ensure overlay is visible for the next pointer
        if !self.pointerOverlayManager.isVisible {
            self.pointerOverlayManager.showOverlay(viewModel: self)
        }

        Task {
            do {
                let result = try await engine.executeInternalText("The click happened and the UI updated. Look at the screenshot carefully. Describe what you SEE on this screen in 1-2 short sentences, then click the next element in the tour using [CLICK:x,y:label]. Guide through whatever app is currently visible — do NOT try to switch apps. If the tour is complete, say a brief wrap-up and use [POINT:none].")
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
                        self.animateStreamingText(responseText)
                        self.handlePointerAndSpeak(pointer: result.2, responseText: responseText)
                    } else {
                        self.guidedModeStepCount = 0
                        self.status = .idle
                        self.statusLine = "All done — I'm here if you need me."
                    }
                }
            } catch {
                await MainActor.run {
                    self.guidedModeStepCount = 0
                    self.status = .idle
                    self.statusLine = "Hmm, lost my way. Try asking again?"
                    self.logger?.log("Guided mode error: \(error.localizedDescription)", tag: "guide")
                }
            }
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
        finishTour()
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
