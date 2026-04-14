import Foundation
import AppKit

/// Watches `NSWorkspace.didActivateApplicationNotification` and calls back
/// whenever a non-Anna app becomes frontmost. The callback receives:
///   - bundle id
///   - localized name
///   - launch-count (1 ⇒ first ever observation — trigger onboarding)
///
/// Owned by `AppContainer`; observer is removed on deinit. Callback runs
/// on the main actor so the caller can safely touch UI / settings.
@MainActor
final class AppActivationObserver {

    /// Callback signature: (bundleID, appName, launchCount, isElectron).
    var onActivation: ((String, String, Int, Bool) -> Void)?

    private let perception: PerceptionEngine
    private var observer: NSObjectProtocol?
    private let ownBundleID: String?
    /// Suppress onboarding for the first N seconds after Anna starts — macOS
    /// often re-focuses several apps during login / Anna launch, and we
    /// don't want to greet the user for Finder on day one.
    private let startupGracePeriod: TimeInterval = 20
    private let startupTime = Date()

    /// Bundle IDs we never want to onboard for. Covers Apple helper
    /// processes that briefly become frontmost (permission prompts, system
    /// UI overlays, auth warnings) plus Finder itself, which is always
    /// running and doesn't meaningfully have a "first launch".
    private static let bundleIDBlocklist: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.UserNotificationCenter",
        "com.apple.coreservices.uiagent",
        "com.apple.accessibility.universalAccessAuthWarn",
        "com.apple.security-agent",
        "com.apple.SecurityAgent",
        "com.apple.TCC.configuration-tool",
        "com.apple.quicklook.ui.helper",
    ]

    private func shouldSkipBundle(_ bundleID: String) -> Bool {
        if Self.bundleIDBlocklist.contains(bundleID) { return true }
        // Any nameless helper / agent (e.g. `*.agent`, `*.helper`, `*.xpc`).
        let lower = bundleID.lowercased()
        if lower.hasSuffix(".agent") || lower.hasSuffix(".helper") ||
           lower.hasSuffix(".xpc") || lower.contains(".agent.") {
            return true
        }
        return false
    }

    init(perception: PerceptionEngine) {
        self.perception = perception
        self.ownBundleID = Bundle.main.bundleIdentifier
    }

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bid = app.bundleIdentifier else { return }
            // Ignore self-activations so Anna doesn't onboard herself.
            if bid == self.ownBundleID { return }
            // Silence Apple system helpers and known-noisy bundles.
            if self.shouldSkipBundle(bid) { return }
            // Skip everything during the startup grace window so we don't
            // onboard for apps macOS re-focuses during login.
            if Date().timeIntervalSince(self.startupTime) < self.startupGracePeriod { return }

            // Let PerceptionEngine bump the per-app counter and tag Electron.
            // (We mirror what snapshotFrontmost would do, but cheaper.)
            let wasFirstBefore = self.perception.isFirstObservation(of: bid)
            let info = self.perception.frontmostApp()
            let launchCount = info?.launchCount ?? 1
            let isElectron = info?.isElectron ?? false
            let name = info?.name ?? app.localizedName ?? bid

            // Only fire the callback on genuine first observation — callers
            // decide what to do with the info, but the counter gate prevents
            // every re-focus from re-onboarding.
            if wasFirstBefore {
                self.onActivation?(bid, name, launchCount, isElectron)
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
