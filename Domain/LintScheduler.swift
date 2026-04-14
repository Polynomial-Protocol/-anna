import Foundation

/// Schedules the weekly wiki lint + index rebuild.
///
/// Spec calls for `BackgroundTasks`, but that framework is primarily for
/// iOS app-suspension flows. On macOS with `LSUIElement=true` Anna runs
/// continuously while the user is logged in, so a plain `Timer` in the
/// app process is simpler, observable, and equivalent.
///
/// Behavior: on start, if ≥7 days have elapsed since the last recorded lint
/// run (UserDefaults key `anna.lastLintAt`), run immediately. Then fire
/// every 24h after that — each tick is a no-op unless the 7-day window is up.
@MainActor
final class LintScheduler {

    private let kb: WikiKnowledgeBase
    private var timer: Timer?
    private let lintIntervalSeconds: TimeInterval = 7 * 24 * 60 * 60
    private let tickSeconds: TimeInterval = 24 * 60 * 60
    private let defaultsKey = "anna.lastLintAt"

    init(kb: WikiKnowledgeBase = .shared) {
        self.kb = kb
    }

    func start() {
        guard timer == nil else { return }
        Task { await runIfDue() }
        timer = Timer.scheduledTimer(
            withTimeInterval: tickSeconds, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in await self?.runIfDue() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func runIfDue() async {
        let last = UserDefaults.standard.object(forKey: defaultsKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= lintIntervalSeconds else { return }
        await kb.lint()
        await kb.writeIndex()
        UserDefaults.standard.set(Date(), forKey: defaultsKey)
    }
}
