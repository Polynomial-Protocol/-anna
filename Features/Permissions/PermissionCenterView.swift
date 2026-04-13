import SwiftUI

struct PermissionCenterView: View {
    @ObservedObject var viewModel: PermissionsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Permission Center")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.85))

                    if viewModel.allGranted {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(hex: "69D3B0"))
                            Text("All permissions granted")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(hex: "69D3B0").opacity(0.7))
                        }
                    } else {
                        Text("Anna needs a few permissions to work properly. Nothing leaves your Mac.")
                            .font(.system(size: 12))
                            .foregroundStyle(.primary.opacity(0.35))
                    }
                }

                // Denied banner
                if !viewModel.deniedPermissions.isEmpty {
                    deniedBanner
                }

                // Permission list
                VStack(spacing: 1) {
                    ForEach(viewModel.statuses) { status in
                        permissionCard(status)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Refresh hint
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                    Text("Permissions refresh automatically when Anna becomes active.")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.primary.opacity(0.2))
                .padding(.top, 4)
            }
            .padding(24)
        }
    }

    // MARK: - Denied Banner

    private var deniedBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "FFC764"))
                Text("Some permissions need attention")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.7))
            }

            let deniedRequired = viewModel.deniedPermissions.filter(\.kind.isRequired)
            if !deniedRequired.isEmpty {
                Text("Required permissions missing: \(deniedRequired.map(\.kind.displayName).joined(separator: ", ")). Core features won't work without these.")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.35))
            } else {
                Text("Optional permissions are missing. Anna works without them, but some features will be limited.")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.35))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "FFC764").opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(hex: "FFC764").opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Permission Card

    private func permissionCard(_ status: PermissionStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: status.kind.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(statusColor(status).opacity(0.7))
                    .frame(width: 20)

                // Name + reason
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(status.kind.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.75))

                        if status.kind.isRequired {
                            Text("Required")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color(hex: "FFC764").opacity(0.7))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color(hex: "FFC764").opacity(0.08), in: Capsule())
                        }
                    }

                    Text(status.kind.reason)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.3))
                        .lineLimit(2)
                }

                Spacer()

                // Status + actions
                statusBadge(status)
            }

            // Recovery instructions when denied
            if status.needsAttention {
                VStack(alignment: .leading, spacing: 8) {
                    Rectangle().fill(.primary.opacity(0.04)).frame(height: 1)
                        .padding(.top, 8)

                    Text(status.kind.denialInstructions)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.35))

                    HStack(spacing: 8) {
                        Button {
                            viewModel.request(status.kind)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 9))
                                Text("Retry")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(.primary.opacity(0.55))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.primary.opacity(0.07), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            viewModel.openSettings(for: status.kind)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "gear")
                                    .font(.system(size: 9))
                                Text("Open System Settings")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(.primary.opacity(0.55))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.primary.opacity(0.07), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Status Badge

    @ViewBuilder
    private func statusBadge(_ status: PermissionStatus) -> some View {
        switch status.state {
        case .granted:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                Text("Granted")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(Color(hex: "69D3B0"))

        case .notRequested:
            Button {
                viewModel.request(status.kind)
            } label: {
                Text("Grant")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.6))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(.primary.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)

        case .denied:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                Text("Denied")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.red.opacity(0.7))

        case .manualStepRequired:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 10))
                Text("Action needed")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(Color(hex: "FFC764").opacity(0.8))
        }
    }

    // MARK: - Helpers

    private func statusColor(_ status: PermissionStatus) -> Color {
        switch status.state {
        case .granted: return Color(hex: "69D3B0")
        case .denied: return .red
        case .manualStepRequired: return Color(hex: "FFC764")
        case .notRequested: return .white
        }
    }
}
