import SwiftUI

struct EventRow: View {
    let event: AssistantEvent

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    Spacer()
                    Text(event.timestamp, style: .time)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Text(event.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }

    private var color: Color {
        switch event.tone {
        case .neutral: return .secondary
        case .success: return AnnaPalette.mint
        case .warning: return AnnaPalette.warning
        case .failure: return .red
        }
    }
}
