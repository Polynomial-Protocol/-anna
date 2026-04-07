import AVFoundation
import Foundation

// MARK: - Voice Info Model

struct VoiceInfo: Identifiable, Hashable {
    let id: String  // identifier
    let name: String
    let language: String
    let quality: VoiceQuality
    let gender: VoiceGender

    enum VoiceQuality: String, Comparable, Codable {
        case `default` = "Default"
        case enhanced = "Enhanced"
        case premium = "Premium"

        static func < (lhs: VoiceQuality, rhs: VoiceQuality) -> Bool {
            let order: [VoiceQuality] = [.default, .enhanced, .premium]
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }
    }

    enum VoiceGender: String, Codable {
        case female = "Female"
        case male = "Male"
        case unknown = "Unknown"
    }
}

// MARK: - TTS Service

@MainActor
final class TTSService: NSObject, ObservableObject {
    @Published var isSpeaking: Bool = false

    private let synthesizer = AVSpeechSynthesizer()
    private var completion: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speak the given text aloud using the specified voice and rate.
    func speak(_ text: String, rate: Float = 0.50, voiceIdentifier: String = "") {
        stop()

        let cleaned = preprocessForSpeech(text)
        guard !cleaned.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.rate = rate
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.05

        // Select voice
        utterance.voice = resolveVoice(identifier: voiceIdentifier)

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    func speakAndWait(_ text: String, rate: Float = 0.50, voiceIdentifier: String = "") async {
        await withCheckedContinuation { continuation in
            completion = {
                continuation.resume()
            }
            speak(text, rate: rate, voiceIdentifier: voiceIdentifier)
        }
    }

    // MARK: - Voice Discovery

    /// Returns all available English voices, sorted by quality (best first).
    static func availableVoices() -> [VoiceInfo] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .map { voice in
                VoiceInfo(
                    id: voice.identifier,
                    name: extractVoiceName(from: voice),
                    language: voice.language,
                    quality: mapQuality(voice),
                    gender: inferGender(from: voice)
                )
            }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality > rhs.quality }
                return lhs.name < rhs.name
            }
    }

    /// Returns the best available voice identifier.
    static func bestAvailableVoiceID() -> String {
        // Priority list of preferred voices
        let preferred = [
            "com.apple.voice.premium.en-US.Zoe",
            "com.apple.voice.premium.en-US.Ava",
            "com.apple.voice.premium.en-GB.Kate",
            "com.apple.voice.premium.en-US.Samantha",
            "com.apple.voice.premium.en-US.Allison",
            "com.apple.voice.premium.en-AU.Karen",
            "com.apple.voice.premium.en-US.Tom",
            "com.apple.voice.enhanced.en-US.Zoe",
            "com.apple.voice.enhanced.en-US.Ava",
            "com.apple.voice.enhanced.en-US.Samantha",
            "com.apple.voice.enhanced.en-GB.Kate",
        ]

        let installed = Set(AVSpeechSynthesisVoice.speechVoices().map(\.identifier))

        for id in preferred {
            if installed.contains(id) { return id }
        }

        // Fallback: best quality English voice available
        let voices = availableVoices()
        return voices.first?.id ?? ""
    }

    // MARK: - Text Preprocessing for Natural Speech

    private func preprocessForSpeech(_ text: String) -> String {
        var result = text

        // Remove [POINT:...] markers
        result = result.replacingOccurrences(
            of: "\\[POINT:[^\\]]*\\]",
            with: "",
            options: .regularExpression
        )

        // Remove markdown formatting
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "__", with: "")
        result = result.replacingOccurrences(of: "```", with: "")
        result = result.replacingOccurrences(of: "`", with: "")
        result = result.replacingOccurrences(of: "###", with: "")
        result = result.replacingOccurrences(of: "##", with: "")
        result = result.replacingOccurrences(of: "# ", with: "")

        // Remove bullet markers
        result = result.replacingOccurrences(
            of: "(?m)^\\s*[-*•]\\s+",
            with: "",
            options: .regularExpression
        )

        // Remove numbered list markers
        result = result.replacingOccurrences(
            of: "(?m)^\\s*\\d+\\.\\s+",
            with: "",
            options: .regularExpression
        )

        // Expand common abbreviations for natural speech
        result = result.replacingOccurrences(of: "e.g.", with: "for example")
        result = result.replacingOccurrences(of: "i.e.", with: "that is")
        result = result.replacingOccurrences(of: "etc.", with: "and so on")
        result = result.replacingOccurrences(of: "vs.", with: "versus")
        result = result.replacingOccurrences(of: "approx.", with: "approximately")

        // Replace em dashes with commas for natural pauses
        result = result.replacingOccurrences(of: " — ", with: ", ")
        result = result.replacingOccurrences(of: "—", with: ", ")
        result = result.replacingOccurrences(of: " – ", with: ", ")
        result = result.replacingOccurrences(of: "–", with: ", ")

        // Replace URLs with "a link" to avoid reading gibberish
        result = result.replacingOccurrences(
            of: "https?://[^\\s]+",
            with: "a link",
            options: .regularExpression
        )

        // Replace file paths with just the filename
        result = result.replacingOccurrences(
            of: "/[\\w/.-]+/(\\w+\\.\\w+)",
            with: "$1",
            options: .regularExpression
        )

        // Add a brief pause (period) after colons that start explanations
        result = result.replacingOccurrences(of: ": ", with: ". ")

        // Clean up excessive whitespace and newlines
        result = result.replacingOccurrences(
            of: "\\n+",
            with: ". ",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "\\s{2,}",
            with: " ",
            options: .regularExpression
        )

        // Clean up double periods
        result = result.replacingOccurrences(of: "..", with: ".")
        result = result.replacingOccurrences(of: ". .", with: ".")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Voice Resolution

    private func resolveVoice(identifier: String) -> AVSpeechSynthesisVoice? {
        // Try the user's chosen voice
        if !identifier.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }

        // Auto-select best available
        let bestID = Self.bestAvailableVoiceID()
        if !bestID.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: bestID) {
            return voice
        }

        // Final fallback
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    // MARK: - Helpers

    private static func extractVoiceName(from voice: AVSpeechSynthesisVoice) -> String {
        // Voice names are like "Samantha" or "Samantha (Enhanced)"
        voice.name
    }

    private static func mapQuality(_ voice: AVSpeechSynthesisVoice) -> VoiceInfo.VoiceQuality {
        let id = voice.identifier.lowercased()
        if id.contains("premium") { return .premium }
        if id.contains("enhanced") { return .enhanced }
        return .default
    }

    private static func inferGender(from voice: AVSpeechSynthesisVoice) -> VoiceInfo.VoiceGender {
        let id = voice.identifier.lowercased()
        let name = voice.name.lowercased()

        let femaleNames = ["samantha", "zoe", "ava", "allison", "kate", "karen",
                          "moira", "fiona", "tessa", "veena", "susan", "serena",
                          "martha", "nicky", "joelle", "sandy", "shelley", "monica"]
        let maleNames = ["tom", "alex", "daniel", "fred", "oliver", "ralph",
                        "rishi", "aaron", "albert", "bruce", "evan", "lee", "nathan"]

        if femaleNames.contains(where: { name.contains($0) || id.contains($0) }) {
            return .female
        }
        if maleNames.contains(where: { name.contains($0) || id.contains($0) }) {
            return .male
        }
        return .unknown
    }
}

// MARK: - Delegate

extension TTSService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.completion?()
            self.completion = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.completion?()
            self.completion = nil
        }
    }
}
