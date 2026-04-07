import Foundation

struct ClaudeCLIResult: Sendable {
    let text: String
    let success: Bool
    let costUSD: Double?
    let durationMs: Int
}
