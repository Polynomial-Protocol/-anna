import Foundation
import Speech

final class AppleSpeechTranscriptionService: VoiceTranscriptionService {
    private let recognizer: SFSpeechRecognizer

    init(locale: Locale = .current) {
        self.recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    }

    func transcribe(_ utterance: CapturedUtterance) async throws -> TranscriptionResult {
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard authStatus == .authorized else {
            throw AnnaError.transcriptionUnavailable
        }

        guard recognizer.isAvailable else {
            throw AnnaError.transcriptionUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: utterance.fileURL)
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: AnnaError.unknown(error.localizedDescription))
                    return
                }
                guard let result, result.isFinal else { return }
                let text = result.bestTranscription.formattedString
                let confidence = Double(
                    result.bestTranscription.segments.map(\.confidence).reduce(0, +)
                    / Float(max(result.bestTranscription.segments.count, 1))
                )
                continuation.resume(returning: TranscriptionResult(text: text, confidence: confidence))
            }
        }
    }
}
