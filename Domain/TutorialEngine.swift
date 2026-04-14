import Foundation
import AppKit

/// Thin wrapper around `AssistantEngine` that generates the three spec-defined
/// tutorial surfaces: first-launch onboarding, contextual tips, and
/// on-demand walkthroughs. Relies on AssistantEngine for the actual LLM
/// round-trip so perception + wiki injection are shared.
@MainActor
final class TutorialEngine {

    private let engine: AssistantEngine
    private let wikiKB: WikiKnowledgeBase
    private let settingsProvider: () -> AppSettings
    private static let confidenceFloor = 40

    init(engine: AssistantEngine, wikiKB: WikiKnowledgeBase = .shared,
         settingsProvider: @escaping () -> AppSettings) {
        self.engine = engine
        self.wikiKB = wikiKB
        self.settingsProvider = settingsProvider
    }

    // MARK: - First-launch onboarding

    /// Generates a brief, one-or-two-sentence orientation tip for an app the
    /// user just opened for the first time. Returns nil when:
    ///   - onboarding is globally disabled
    ///   - user suppressed onboarding for this bundle id
    ///   - confidence is below the anti-hallucination floor and no wiki exists
    func generateFirstLaunchTip(bundleID: String, appName: String) async -> String? {
        let settings = settingsProvider()
        guard settings.onboardingEnabled else { return nil }
        guard !settings.suppressedOnboardingBundleIDs.contains(bundleID) else { return nil }

        let confidence = await wikiKB.readConfidence(bundleID: bundleID)
        let wiki = await wikiKB.readAppWiki(bundleID: bundleID)
        if wiki == nil && confidence < Self.confidenceFloor {
            // We know nothing about this app yet — log a gap instead of guessing.
            await LearningLoop.shared.recordLowConfidenceSkip(
                bundleID: bundleID, query: "first-launch onboarding")
            return nil
        }

        let prompt = """
        [first-launch onboarding] The user just opened \(appName) for the first time.
        Say ONE friendly sentence describing the single most useful thing to do
        first. Keep it under 120 characters. If you can point at a button with
        [POINT:x,y:label], do so. No preamble, no greeting, no emoji.
        """
        do {
            let (_, outcome, _) = try await engine.executeInternalText(prompt)
            if case .completed(let summary, _) = outcome, !summary.isEmpty {
                return summary
            }
        } catch {
            return nil
        }
        return nil
    }

    // MARK: - Contextual tip (screen-state delta)

    /// Fired when the user has paused inside an app and we want to offer a
    /// small next-step nudge. Confidence-gated like onboarding. Returns nil
    /// when we shouldn't surface anything.
    func generateContextualTip(bundleID: String, appName: String) async -> String? {
        let settings = settingsProvider()
        guard !settings.suppressedOnboardingBundleIDs.contains(bundleID) else { return nil }

        let confidence = await wikiKB.readConfidence(bundleID: bundleID)
        if confidence < Self.confidenceFloor {
            await LearningLoop.shared.recordLowConfidenceSkip(
                bundleID: bundleID, query: "contextual tip")
            return nil
        }

        let prompt = """
        [contextual tip] The user is inside \(appName) and just paused. Offer
        ONE short, specific next-step nudge based on what's on screen. Under
        120 characters, no greeting, no filler. If nothing genuinely useful
        to say, reply with just the word "SKIP".
        """
        do {
            let (_, outcome, _) = try await engine.executeInternalText(prompt)
            if case .completed(let summary, _) = outcome {
                let t = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty || t.uppercased().contains("SKIP") { return nil }
                return t
            }
        } catch {
            return nil
        }
        return nil
    }

    // MARK: - Walkthrough (explicit user request)

    /// Structured step generated on demand. Each step is a short action. The
    /// model returns JSON; we parse leniently — if parsing fails, fall back
    /// to splitting the reply on newlines.
    struct WalkthroughStep: Sendable, Codable {
        let title: String
        let body: String
    }

    func generateWalkthrough(task: String, appName: String) async -> [WalkthroughStep] {
        let prompt = """
        [walkthrough request] The user wants to: "\(task)" in \(appName).
        Produce a short step-by-step plan. Each step = one concrete action.
        Max 8 steps, sequential. Return ONLY a JSON array of objects with
        `title` and `body` keys (body ≤ 140 chars). No preamble, no fences.
        """
        do {
            let (_, outcome, _) = try await engine.executeInternalText(prompt)
            guard case .completed(let text, _) = outcome else { return [] }
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = cleaned.data(using: .utf8),
               let steps = try? JSONDecoder().decode([WalkthroughStep].self, from: data) {
                return steps
            }
            // Lenient fallback: numbered lines → steps.
            let lines = cleaned.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return lines.prefix(8).enumerated().map { i, line in
                WalkthroughStep(title: "Step \(i + 1)", body: line)
            }
        } catch {
            return []
        }
    }
}
