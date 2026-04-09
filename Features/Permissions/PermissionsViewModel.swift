import SwiftUI
import Combine

@MainActor
final class PermissionsViewModel: ObservableObject {
    @Published var statuses: [PermissionStatus]

    private let permissionService: PermissionService
    private var cancellables = Set<AnyCancellable>()

    var allGranted: Bool {
        statuses.allSatisfy(\.isGranted)
    }

    var requiredGranted: Bool {
        statuses.filter { $0.kind.isRequired }.allSatisfy(\.isGranted)
    }

    var deniedPermissions: [PermissionStatus] {
        statuses.filter(\.needsAttention)
    }

    init(permissionService: PermissionService) {
        self.permissionService = permissionService
        self.statuses = permissionService.currentStatuses()
        observeAppActivation()
    }

    func refresh() {
        statuses = permissionService.refresh()
    }

    func request(_ kind: PermissionKind) {
        Task {
            let updated = await permissionService.request(kind)
            self.statuses.removeAll { $0.kind == kind }
            self.statuses.append(updated)
            self.statuses.sort { $0.kind.onboardingOrder < $1.kind.onboardingOrder }
        }
    }

    func openSettings(for kind: PermissionKind) {
        permissionService.openSystemSettings(for: kind)
    }

    func statusFor(_ kind: PermissionKind) -> PermissionStatus? {
        statuses.first { $0.kind == kind }
    }

    // MARK: - App Activation Observer

    /// Refresh permissions whenever the app becomes active (e.g. user returns from System Settings)
    private func observeAppActivation() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }
}
