import SwiftUI

@MainActor
final class PermissionsViewModel: ObservableObject {
    @Published var statuses: [PermissionStatus]

    private let permissionService: PermissionService

    init(permissionService: PermissionService) {
        self.permissionService = permissionService
        self.statuses = permissionService.currentStatuses()
    }

    func refresh() {
        statuses = permissionService.refresh()
    }

    func request(_ kind: PermissionKind) {
        Task {
            let updated = await permissionService.request(kind)
            await MainActor.run {
                self.statuses.removeAll { $0.kind == kind }
                self.statuses.append(updated)
                self.statuses.sort { $0.kind.rawValue < $1.kind.rawValue }
            }
        }
    }

    func openSettings(for kind: PermissionKind) {
        permissionService.openSystemSettings(for: kind)
    }
}
