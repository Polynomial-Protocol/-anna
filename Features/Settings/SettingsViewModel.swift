import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings
    private let updater: (AppSettings) -> Void

    init(settings: AppSettings, updater: @escaping (AppSettings) -> Void) {
        self.settings = settings
        self.updater = updater
    }

    func persist() {
        settings.save()
        updater(settings)
    }
}
