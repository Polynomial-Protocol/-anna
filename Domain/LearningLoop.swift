import Foundation

/// Outcome tracker that feeds the self-growing knowledge base.
///
/// Called from `AssistantEngine` / `AssistantViewModel` on explicit user
/// signals (tip followed, tip dismissed, query unanswered). Confidence
/// deltas follow the schema in `wiki/schema.md`.
actor LearningLoop {
    static let shared = LearningLoop()

    private let kb: WikiKnowledgeBase

    init(kb: WikiKnowledgeBase = .shared) {
        self.kb = kb
    }

    /// User followed the suggestion → reinforce the app's confidence.
    func recordSuccess(bundleID: String) async {
        await kb.adjustConfidence(bundleID: bundleID, delta: 5)
        await kb.appendLog("success +5 for \(bundleID)")
    }

    /// User completed a full walkthrough → stronger reinforcement.
    func recordWalkthroughCompleted(bundleID: String) async {
        await kb.adjustConfidence(bundleID: bundleID, delta: 10)
        await kb.appendLog("walkthrough-complete +10 for \(bundleID)")
    }

    /// User dismissed a tip → small drop, log the context as a gap.
    func recordDismissal(bundleID: String, context: String) async {
        await kb.logGap(query: context, bundleID: bundleID, reason: .dismissed)
    }

    /// The model refused to help because confidence was too low.
    func recordLowConfidenceSkip(bundleID: String, query: String) async {
        await kb.logGap(query: query, bundleID: bundleID, reason: .lowConfidence)
    }

    /// User asked again or the answer clearly missed — log as unanswered.
    func recordGap(bundleID: String, query: String) async {
        await kb.logGap(query: query, bundleID: bundleID, reason: .unanswered)
    }
}
