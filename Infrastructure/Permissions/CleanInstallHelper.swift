import Foundation

/// Detects fresh installs and version upgrades. Runs migrations on upgrade,
/// but NEVER wipes user data.
enum CleanInstallHelper {

    private static let lastKnownVersionKey = "anna_lastKnownBuildVersion"
    private static let firstLaunchCompleteKey = "anna_firstLaunchComplete"

    static func performIfNeeded() {
        let defaults = UserDefaults.standard
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"

        let hasLaunchedBefore = defaults.bool(forKey: firstLaunchCompleteKey)
        let previousBuild = defaults.string(forKey: lastKnownVersionKey)

        if !hasLaunchedBefore {
            // Genuine first install — no data to preserve
            defaults.set(true, forKey: firstLaunchCompleteKey)
            defaults.set(currentBuild, forKey: lastKnownVersionKey)
        } else if previousBuild != currentBuild {
            // App was updated — run migrations, preserve all user data
            MigrationManager.migrateIfNeeded(from: previousBuild ?? "0", to: currentBuild)
            defaults.set(currentBuild, forKey: lastKnownVersionKey)
        }
    }
}
