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
    private var piperProcess: Process?
    private var audioPlayer: AVAudioPlayer?

    // Piper TTS — bundled resources are set up in a working directory at ~/.anna/piper-runtime/
    private static let piperRuntimeDir = "\(NSHomeDirectory())/.anna/piper-runtime"
    private static var piperPath: String { piperRuntimeDir + "/piper" }
    private static var piperModelPath: String { piperRuntimeDir + "/en-us-lessac-medium.onnx" }

    static var isPiperAvailable: Bool {
        // Ensure runtime directory is set up from bundled resources
        setupPiperRuntime()
        return FileManager.default.fileExists(atPath: piperPath) &&
               FileManager.default.fileExists(atPath: piperModelPath)
    }

    /// Copies bundled piper folder from app bundle into ~/.anna/piper-runtime/
    /// The bundle uses a folder reference so directory structure is preserved.
    private static func setupPiperRuntime() {
        let fm = FileManager.default
        let runtimeDir = piperRuntimeDir
        let markerFile = runtimeDir + "/.setup-complete"

        // Skip if already set up
        if fm.fileExists(atPath: markerFile) { return }

        // The piper folder is bundled as a folder reference at Resources/piper/
        guard let bundledPiperDir = Bundle.main.resourceURL?.appendingPathComponent("piper").path,
              fm.fileExists(atPath: bundledPiperDir + "/piper") else { return }

        // Copy the entire piper folder to runtime location
        try? fm.removeItem(atPath: runtimeDir)
        try? fm.copyItem(atPath: bundledPiperDir, toPath: runtimeDir)

        // Make piper executable
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtimeDir + "/piper")

        // Mark setup complete
        fm.createFile(atPath: markerFile, contents: nil)
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speak the given text aloud. Uses Piper neural TTS if available, falls back to Apple TTS.
    func speak(_ text: String, rate: Float = 0.50, voiceIdentifier: String = "") {
        stop()

        let cleaned = preprocessForSpeech(text)
        guard !cleaned.isEmpty else { return }

        if Self.isPiperAvailable {
            isSpeaking = true
            speakWithPiper(cleaned, rate: rate)
        } else {
            isSpeaking = true
            speakWithApple(cleaned, rate: rate, voiceIdentifier: voiceIdentifier)
        }
    }

    func stop() {
        piperProcess?.terminate()
        piperProcess = nil
        audioPlayer?.stop()
        audioPlayer = nil
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

    // MARK: - Piper Neural TTS

    private func speakWithPiper(_ text: String, rate: Float) {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("anna-tts-\(UUID().uuidString).wav")
        let piperExe = Self.piperPath
        let modelPath = Self.piperModelPath
        let lengthScale = Self.piperLengthScale(from: rate)

        Task.detached { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: piperExe)
            process.arguments = [
                "--model", modelPath,
                "--output_file", tempFile.path,
                "--length_scale", String(format: "%.2f", lengthScale)
            ]

            // Set working directory to piper runtime dir so it finds dylibs and espeak-ng-data
            let piperDir = (piperExe as NSString).deletingLastPathComponent
            process.currentDirectoryURL = URL(fileURLWithPath: piperDir)

            var env = ProcessInfo.processInfo.environment
            env["DYLD_LIBRARY_PATH"] = piperDir
            env["ESPEAK_DATA_PATH"] = piperDir + "/espeak-ng-data"
            process.environment = env

            let inputPipe = Pipe()
            process.standardInput = inputPipe
            process.standardError = Pipe()  // Capture stderr for debugging

            do {
                try process.run()
                inputPipe.fileHandleForWriting.write(text.data(using: .utf8) ?? Data())
                inputPipe.fileHandleForWriting.closeFile()
                process.waitUntilExit()

                await MainActor.run { [weak self] in
                    guard let self, self.isSpeaking else { return }
                    self.playWavFile(tempFile)
                }
            } catch {
                await MainActor.run { [weak self] in
                    // Piper failed, fall back to Apple TTS
                    self?.speakWithApple(text, rate: rate, voiceIdentifier: "")
                }
            }
        }
    }

    private func playWavFile(_ url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.play()
        } catch {
            isSpeaking = false
            completion?()
            completion = nil
        }
    }

    /// Convert AVSpeechUtterance rate (0.3-0.65) to Piper length_scale (lower = faster)
    private static func piperLengthScale(from rate: Float) -> Float {
        // rate 0.3 (slow) → length_scale 1.3, rate 0.5 (normal) → 1.0, rate 0.65 (fast) → 0.75
        let normalized = (rate - 0.3) / 0.35  // 0.0 to 1.0
        return 1.3 - (normalized * 0.55)
    }

    // MARK: - Apple TTS Fallback

    private func speakWithApple(_ text: String, rate: Float, voiceIdentifier: String) {
        let voice = resolveVoice(identifier: voiceIdentifier)
        let chunks = splitIntoChunks(text)

        for (index, chunk) in chunks.enumerated() {
            let ssml = buildSSML(text: chunk, rate: rate)
            let utterance: AVSpeechUtterance
            if let ssmlUtterance = AVSpeechUtterance(ssmlRepresentation: ssml) {
                utterance = ssmlUtterance
            } else {
                utterance = AVSpeechUtterance(string: chunk)
                utterance.rate = rate
                utterance.pitchMultiplier = 1.02
            }
            utterance.volume = 1.0
            utterance.preUtteranceDelay = index == 0 ? 0.15 : 0.05
            utterance.postUtteranceDelay = 0.08
            utterance.voice = voice
            synthesizer.speak(utterance)
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
        // Priority list: Samantha first (default), then premium/enhanced variants
        let preferred = [
            "com.apple.voice.premium.en-US.Samantha",
            "com.apple.voice.enhanced.en-US.Samantha",
            "com.apple.voice.compact.en-US.Samantha",
            "com.apple.voice.premium.en-US.Zoe",
            "com.apple.voice.premium.en-US.Ava",
            "com.apple.voice.premium.en-GB.Kate",
            "com.apple.voice.premium.en-US.Allison",
            "com.apple.voice.premium.en-AU.Karen",
            "com.apple.voice.enhanced.en-US.Zoe",
            "com.apple.voice.enhanced.en-US.Ava",
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

    /// Recommended male voice identifier (Daniel, British English).
    static let recommendedMaleVoiceID = "com.apple.voice.compact.en-GB.Daniel"

    // MARK: - SSML Builder

    private func buildSSML(text: String, rate: Float) -> String {
        // Map AVSpeechUtterance rate (0.0-1.0) to SSML rate percentage
        // 0.5 = 100% (normal), 0.3 = 80%, 0.65 = 120%
        let ssmlRate = Int(60 + (rate * 120))

        // Escape XML special characters
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        // Add breaks after sentence-ending punctuation for natural rhythm
        var withBreaks = escaped
            .replacingOccurrences(of: ". ", with: ".<break time=\"280ms\"/> ")
            .replacingOccurrences(of: "? ", with: "?<break time=\"350ms\"/> ")
            .replacingOccurrences(of: "! ", with: "!<break time=\"300ms\"/> ")
            .replacingOccurrences(of: ", ", with: ",<break time=\"120ms\"/> ")

        // Add a brief pause after colons
        withBreaks = withBreaks.replacingOccurrences(of: ": ", with: ":<break time=\"200ms\"/> ")

        return """
        <speak><prosody rate="\(ssmlRate)%" pitch="+2%">\(withBreaks)</prosody></speak>
        """
    }

    // MARK: - Sentence Chunking

    private func splitIntoChunks(_ text: String) -> [String] {
        // Split on sentence boundaries, group into 2-3 sentence chunks
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if sentences.count <= 3 { return [text] }

        var chunks: [String] = []
        var current: [String] = []
        for sentence in sentences {
            current.append(sentence)
            if current.count >= 2 {
                chunks.append(current.joined(separator: ". ") + ".")
                current = []
            }
        }
        if !current.isEmpty {
            chunks.append(current.joined(separator: ". ") + ".")
        }
        return chunks
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

        // Remove markdown links — keep only the display text: [text](url) → text
        result = result.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\([^)]+\\)",
            with: "$1",
            options: .regularExpression
        )

        // Remove all URLs (http, https, www, and bare domains with paths)
        result = result.replacingOccurrences(
            of: "https?://[^\\s),]+",
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "www\\.[^\\s),]+",
            with: "",
            options: .regularExpression
        )
        // Bare domain-like patterns: word.com/path, amazon.com, etc.
        result = result.replacingOccurrences(
            of: "\\b[a-zA-Z0-9-]+\\.(com|org|net|io|co|app|dev|ai|shop|store|me|us|uk|ca|au)[/\\w.-]*",
            with: "",
            options: .regularExpression
        )

        // Remove file paths
        result = result.replacingOccurrences(
            of: "(?:/[\\w.-]+){2,}",
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "~/[\\w/.-]+",
            with: "",
            options: .regularExpression
        )

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

        // Remove "Here are the steps:" / "Here's what I found:" style headers
        result = result.replacingOccurrences(
            of: "(?i)here(?:'s| is| are)\\s+(?:the )?(?:steps?|links?|results?|options?|some)\\s*:?",
            with: "",
            options: .regularExpression
        )

        // Remove parenthetical link/source references: (source), (link), (via ...), (from ...)
        result = result.replacingOccurrences(
            of: "\\((?:source|link|via|from|see|ref|available at)[^)]*\\)",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Remove price comparison list patterns like "$XX.XX on StoreName"
        // but keep the first mention
        result = result.replacingOccurrences(
            of: "(?i)(?:also )?(?:available|found|listed|sold) (?:on|at|from) [^.]+",
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

        // Clean up excessive whitespace and newlines
        result = result.replacingOccurrences(
            of: "\\n+",
            with: " ",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "\\s{2,}",
            with: " ",
            options: .regularExpression
        )

        // Clean up punctuation artifacts from removed content
        result = result.replacingOccurrences(of: "..", with: ".")
        result = result.replacingOccurrences(of: ". .", with: ".")
        result = result.replacingOccurrences(of: ", ,", with: ",")
        result = result.replacingOccurrences(of: "  ", with: " ")
        result = result.replacingOccurrences(of: " .", with: ".")
        result = result.replacingOccurrences(of: " ,", with: ",")
        result = result.replacingOccurrences(of: ": .", with: ".")
        result = result.replacingOccurrences(of: ": ,", with: ",")

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

extension TTSService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isSpeaking = false
            self.completion?()
            self.completion = nil
            // Clean up temp file
            if let url = self.audioPlayer?.url {
                try? FileManager.default.removeItem(at: url)
            }
            self.audioPlayer = nil
        }
    }
}

extension TTSService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // Only mark done when the synthesizer has no more queued utterances
            if !synthesizer.isSpeaking {
                self.isSpeaking = false
                self.completion?()
                self.completion = nil
            }
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
