import Foundation

/// Structured tour event tracking for B2B analytics.
/// Currently logs to RuntimeLogger. Can be swapped to PostHog/Mixpanel later.
@MainActor
final class TourAnalytics {
    private weak var logger: RuntimeLogger?

    init(logger: RuntimeLogger?) {
        self.logger = logger
    }

    // MARK: - Tour Events

    func tourStarted(tourGuideID: String, tourName: String) {
        log(TourEvent(
            type: .tourStarted,
            tourGuideID: tourGuideID,
            tourName: tourName,
            stepIndex: 0
        ))
    }

    func stepShown(stepIndex: Int, elementLabel: String?) {
        log(TourEvent(
            type: .stepShown,
            stepIndex: stepIndex,
            elementLabel: elementLabel
        ))
    }

    func stepClicked(stepIndex: Int, clickTarget: String?, durationMs: Int) {
        log(TourEvent(
            type: .stepClicked,
            stepIndex: stepIndex,
            elementLabel: clickTarget,
            durationMs: durationMs
        ))
    }

    func tourAbandoned(stepIndex: Int, reason: String, totalDurationMs: Int) {
        log(TourEvent(
            type: .tourAbandoned,
            stepIndex: stepIndex,
            elementLabel: reason,
            durationMs: totalDurationMs
        ))
    }

    func tourCompleted(totalSteps: Int, totalDurationMs: Int) {
        log(TourEvent(
            type: .tourCompleted,
            stepIndex: totalSteps,
            durationMs: totalDurationMs
        ))
    }

    // MARK: - Internal

    private func log(_ event: TourEvent) {
        let json = """
        {"event":"\(event.type.rawValue)","tour":"\(event.tourName ?? "")","step":\(event.stepIndex),"label":"\(event.elementLabel ?? "")","duration_ms":\(event.durationMs ?? 0),"timestamp":"\(ISO8601DateFormatter().string(from: event.timestamp))"}
        """
        logger?.log(json, tag: "tour-analytics")
    }
}

// MARK: - Tour Event Model

struct TourEvent: Sendable {
    enum EventType: String, Sendable {
        case tourStarted = "tour_started"
        case stepShown = "tour_step_shown"
        case stepClicked = "tour_step_clicked"
        case tourAbandoned = "tour_abandoned"
        case tourCompleted = "tour_completed"
    }

    let type: EventType
    var tourGuideID: String? = nil
    var tourName: String? = nil
    var stepIndex: Int = 0
    var elementLabel: String? = nil
    var durationMs: Int? = nil
    let timestamp: Date = Date()
}
