import AVFoundation
import Foundation

final class HoldToTalkAudioRecorder: NSObject, AudioCaptureService {
    private let recorderQueue = DispatchQueue(label: "anna.audio.capture")
    private var audioRecorder: AVAudioRecorder?
    private var startDate: Date?

    func beginCapture() async throws {
        let url = Self.makeTempURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.prepareToRecord()
            recorder.record()
            audioRecorder = recorder
            startDate = Date()
        } catch {
            throw AnnaError.audioCaptureFailed(error.localizedDescription)
        }
    }

    func finishCapture() async throws -> CapturedUtterance {
        guard let audioRecorder else {
            throw AnnaError.audioCaptureFailed("No active recorder.")
        }

        audioRecorder.stop()
        let duration = Date().timeIntervalSince(startDate ?? Date())
        self.audioRecorder = nil
        self.startDate = nil
        return CapturedUtterance(fileURL: audioRecorder.url, duration: duration)
    }

    func cancelCapture() async {
        audioRecorder?.stop()
        audioRecorder = nil
        startDate = nil
    }

    private static func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
    }
}
