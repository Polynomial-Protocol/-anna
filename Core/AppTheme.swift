import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

enum AnnaPalette {
    // Dark theme
    static let canvas = Color(red: 0.07, green: 0.07, blue: 0.10)
    static let pane = Color(red: 0.10, green: 0.10, blue: 0.14)
    static let surface = Color(red: 0.13, green: 0.13, blue: 0.17)
    static let sidebar = Color(red: 0.08, green: 0.08, blue: 0.11)

    // Accent colors
    static let accent = Color(red: 0.85, green: 0.18, blue: 0.18)
    static let userGradientStart = Color(red: 0.30, green: 0.42, blue: 0.90)
    static let userGradientEnd = Color(red: 0.24, green: 0.34, blue: 0.78)

    // Named colors
    static let cobalt = Color(hex: "14395B")
    static let copper = Color(hex: "D67A43")
    static let cloud = Color(hex: "F3EEE8")
    static let mint = Color(hex: "69D3B0")
    static let warning = Color(hex: "FFC764")
    static let panel = Color.white.opacity(0.08)
}

enum AnnaStatus: String, CaseIterable, Sendable {
    case idle
    case listening
    case thinking
    case acting
    case speaking

    var iconName: String {
        switch self {
        case .idle: return "waveform.circle"
        case .listening: return "mic.fill"
        case .thinking: return "brain"
        case .acting: return "bolt.fill"
        case .speaking: return "speaker.wave.2.fill"
        }
    }

    var displayText: String {
        switch self {
        case .idle: return ""
        case .listening: return "Listening\u{2026}"
        case .thinking: return "Thinking\u{2026}"
        case .acting: return "On it\u{2026}"
        case .speaking: return "Speaking\u{2026}"
        }
    }

    /// Whether this state should show a visible overlay
    var isActive: Bool { self != .idle }

    var color: Color {
        switch self {
        case .idle: return .white.opacity(0.3)
        case .listening: return .white
        case .thinking: return .white.opacity(0.8)
        case .acting: return .white.opacity(0.8)
        case .speaking: return .white.opacity(0.7)
        }
    }
}
