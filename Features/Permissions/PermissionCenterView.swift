import SwiftUI

struct PermissionCenterView: View {
    @ObservedObject var viewModel: PermissionsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Permissions")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))

                Text("I need a few permissions to help you out. Nothing shady, promise.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))

                VStack(spacing: 1) {
                    ForEach(viewModel.statuses) { status in
                        permRow(status)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(24)
        }
    }

    private func permRow(_ status: PermissionStatus) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: status.kind))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(status.kind.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(status.kind.reason)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Spacer()

            if status.state == .granted {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: "69D3B0"))
            } else {
                HStack(spacing: 6) {
                    Button {
                        viewModel.request(status.kind)
                    } label: {
                        Text("Grant")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        viewModel.openSettings(for: status.kind)
                    } label: {
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .help("Open System Settings")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.03))
    }

    private func iconName(for kind: PermissionKind) -> String {
        switch kind {
        case .microphone: return "mic"
        case .accessibility: return "hand.point.up.left"
        case .automation: return "gearshape.2"
        case .screenRecording: return "rectangle.dashed.badge.record"
        }
    }
}
