import SwiftUI

struct PermissionCenterView: View {
    @ObservedObject var viewModel: PermissionsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Permissions")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))

                Text("Anna asks for permissions only because each one unlocks a concrete capability.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))

                ForEach(viewModel.statuses) { status in
                    permissionCard(status)
                }
            }
            .padding(28)
        }
        .background(AnnaPalette.pane)
    }

    private func permissionCard(_ status: PermissionStatus) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(status.kind.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text(status.kind.reason)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                Text(status.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                StatusPill(text: status.state.rawValue.capitalized, color: color(for: status.state))
                Button("Request") {
                    viewModel.request(status.kind)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("Open Settings") {
                    viewModel.openSettings(for: status.kind)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AnnaPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private func color(for state: PermissionState) -> Color {
        switch state {
        case .granted:
            return AnnaPalette.mint
        case .denied:
            return .red
        case .manualStepRequired:
            return AnnaPalette.warning
        case .notRequested:
            return AnnaPalette.copper
        }
    }
}
