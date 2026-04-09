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

    private let engine: AssistantEngine
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
        statusLine = mode == .assistantCommand ? "I'm listening..." : "Go ahead, I'll type it out..."
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
                    self.logger?.log("Transcription: \"\(result.0)\"", tag: "voice")

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

                        // Handle pointer if present
                        if let pointer = result.2 {
                            let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
                            self.pointerOverlayManager.pointAt(pointer, screenSize: screenSize)
                            // Auto-hide pointer after 5 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                                self.pointerOverlayManager.hide()
                            }
                        }

                        // Speak the response if TTS is enabled
                        let settings = self.settingsProvider()
                        if settings.ttsEnabled {
                            self.status = .speaking
                            self.ttsService.speak(responseText, rate: settings.ttsRate, voiceIdentifier: settings.ttsVoiceIdentifier)
                            // Reset status when done speaking
                            Task {
                                while self.ttsService.isSpeaking {
                                    try? await Task.sleep(nanoseconds: 200_000_000)
                                }
                                await MainActor.run {
                                    if self.status == .speaking {
                                        self.status = .idle
                                        self.statusLine = "All done — I'm here if you need me."
                                    }
                                }
                            }
                        } else {
                            self.status = .idle
                            self.statusLine = "All done — I'm here if you need me."
                        }
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
                    self.logger?.log("Text result: \"\(result.0)\"", tag: "text")

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

                        if let pointer = result.2 {
                            let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
                            self.pointerOverlayManager.pointAt(pointer, screenSize: screenSize)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                                self.pointerOverlayManager.hide()
                            }
                        }

                        let settings = self.settingsProvider()
                        if settings.ttsEnabled {
                            self.status = .speaking
                            self.ttsService.speak(responseText, rate: settings.ttsRate, voiceIdentifier: settings.ttsVoiceIdentifier)
                            Task {
                                while self.ttsService.isSpeaking {
                                    try? await Task.sleep(nanoseconds: 200_000_000)
                                }
                                await MainActor.run {
                                    if self.status == .speaking {
                                        self.status = .idle
                                        self.statusLine = "All done — I'm here if you need me."
                                    }
                                }
                            }
                        } else {
                            self.status = .idle
                            self.statusLine = "All done — I'm here if you need me."
                        }
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
