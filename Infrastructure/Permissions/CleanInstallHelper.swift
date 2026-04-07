import Foundation

/// Ensures a clean slate on fresh installs by detecting when the app has been
/// reinstalled and clearing any stale UserDefaults / cached state.
enum CleanInstallHelper {

    private static let lastKnownVersionKey = "anna_lastKnownBuildVersion"
    private static let firstLaunchCompleteKey = "anna_firstLaunchComplete"

    static func performIfNeeded() {
        let defaults = UserDefaults.standard
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"

        let hasLaunchedBefore = defaults.bool(forKey: firstLaunchCompleteKey)
        let previousBuild = defaults.string(forKey: lastKnownVersionKey)

        if !hasLaunchedBefore || previousBuild != currentBuild {
            if let bundleID = Bundle.main.bundleIdentifier {
                defaults.removePersistentDomain(forName: bundleID)
            }
            defaults.set(true, forKey: firstLaunchCompleteKey)
            defaults.set(currentBuild, forKey: lastKnownVersionKey)
            defaults.synchronize()
        }
    }
}
