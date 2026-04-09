import Foundation

enum MigrationManager {
    /// Runs sequential migrations based on build number.
    /// Add new migration cases as the app evolves.
    static func migrateIfNeeded(from oldBuild: String, to newBuild: String) {
        // let oldNum = Int(oldBuild) ?? 0

        // Example: when bumping to build 2, add:
        // if oldNum < 2 { migrateToV2() }

        // No migrations needed yet — this is scaffolding for future versions.
    }
}
