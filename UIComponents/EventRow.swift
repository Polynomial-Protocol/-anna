import SwiftUI

struct EventRow: View {
    let event: AssistantEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(toneColor)
                .frame(width: 5, height: 5)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(event.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(event.timestamp, style: .time)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }
                Text(event.body)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var toneColor: Color {
        switch event.tone {
        case .neutral: return .white.opacity(0.2)
        case .success: return Color(hex: "69D3B0")
        case .warning: return Color(hex: "FFC764")
        case .failure: return .red.opacity(0.7)
        }
    }
}
