import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(FluidAudio)
import FluidAudio
#endif

final class ParakeetTranscriptionService: VoiceTranscriptionService {
    private let modelService: SpeechModelService

    #if canImport(FluidAudio)
    private var cachedManager: AsrManager?
    #endif

    init(modelService: SpeechModelService) {
        self.modelService = modelService
    }

    func transcribe(_ utterance: CapturedUtterance) async throws -> TranscriptionResult {
        let status = await modelService.status()
        if status.state != .ready {
            _ = try? await modelService.prepareModel()
            let retryStatus = await modelService.status()
            guard retryStatus.state == .ready else {
                throw AnnaError.transcriptionUnavailable
            }
        }

        #if canImport(FluidAudio)
        if cachedManager == nil {
            let models = try await AsrModels.downloadAndLoad(version: .v2)
            let manager = AsrManager()
            try await manager.loadModels(models)
            cachedManager = manager
        }

        guard let manager = cachedManager else {
            throw AnnaError.transcriptionUnavailable
        }

        let result = try await manager.transcribe(utterance.fileURL)
        return TranscriptionResult(text: result.text, confidence: 0.9)
        #else
        throw AnnaError.transcriptionUnavailable
        #endif
    }
}
