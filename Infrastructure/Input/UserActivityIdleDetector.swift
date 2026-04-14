import AppKit
import Combine

/// Monitors keyboard and mouse activity to detect when the user has paused after doing
/// something. Used by tutor mode to trigger proactive observations at natural break
/// points rather than on a fixed timer.
///
/// Ported from Clicky-tutor (danpeg/clicky) with thanks.
@MainActor
final class UserActivityIdleDetector: ObservableObject {
    /// Seconds of inactivity before the user is considered idle.
    static let idleThresholdSeconds: TimeInterval = 3.0

    /// True when the user has been idle for longer than the threshold AND has
    /// performed at least one action since the previous observation. Prevents
    /// repeated fires while the user is AFK or listening to TTS.
    @Published private(set) var isUserIdle: Bool = false

    private var lastUserInputTimestamp: Date = Date()
    private(set) var lastClickTimestamp: Date?
    private var hasUserActedSinceLastObservation: Bool = true
    private var globalEventMonitor: Any?
    private var idleCheckTimer: Timer?

    /// Seconds since the user last moved/typed/clicked. Useful for callers that want
    /// a shorter-than-default threshold (e.g. teach mode).
    var secondsSinceLastInput: TimeInterval {
        Date().timeIntervalSince(lastUserInputTimestamp)
    }

    func start() {
        guard globalEventMonitor == nil else { return }
        lastUserInputTimestamp = Date()
        hasUserActedSinceLastObservation = true

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .rightMouseDown,
                       .keyDown, .scrollWheel, .leftMouseDragged]
        ) { [weak self] event in
            let isClick = event.type == .leftMouseDown || event.type == .rightMouseDown
            Task { @MainActor [weak self] in
                self?.recordUserActivity(isClick: isClick)
            }
        }

        idleCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateIdleState()
            }
        }
    }

    func stop() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        idleCheckTimer?.invalidate()
        idleCheckTimer = nil
        isUserIdle = false
    }

    /// Resets the activity flag so the next observation requires fresh user input.
    func observationDidComplete() {
        hasUserActedSinceLastObservation = false
        isUserIdle = false
    }

    private func recordUserActivity(isClick: Bool = false) {
        lastUserInputTimestamp = Date()
        if isClick { lastClickTimestamp = lastUserInputTimestamp }
        hasUserActedSinceLastObservation = true
        isUserIdle = false
    }

    /// Clears the last-click marker so a teach-mode waiter doesn't match a stale click.
    func resetClickMarker() { lastClickTimestamp = nil }

    private func evaluateIdleState() {
        let secondsSinceLastInput = Date().timeIntervalSince(lastUserInputTimestamp)
        let isNowIdle = secondsSinceLastInput >= Self.idleThresholdSeconds
                        && hasUserActedSinceLastObservation
        if isNowIdle != isUserIdle {
            isUserIdle = isNowIdle
        }
    }
}
