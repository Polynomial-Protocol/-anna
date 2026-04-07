import Foundation

#if canImport(FluidAudio)
import FluidAudio
#endif

actor FluidAudioSpeechModelService: SpeechModelService {
    private var cachedStatus = SpeechModelStatus(
        kind: .parakeetV2English,
        state: .notInstalled,
        detail: "Checking model state..."
    )
    private var hasProbed = false

    func status() async -> SpeechModelStatus {
        if !hasProbed {
            hasProbed = true
            #if canImport(FluidAudio)
            do {
                _ = try await AsrModels.downloadAndLoad(version: .v2)
                cachedStatus = SpeechModelStatus(
                    kind: .parakeetV2English,
                    state: .ready,
                    detail: "Parakeet v2 English is ready."
                )
            } catch {
                cachedStatus = SpeechModelStatus(
                    kind: .parakeetV2English,
                    state: .notInstalled,
                    detail: "Model not yet downloaded."
                )
            }
            #else
            cachedStatus = SpeechModelStatus(
                kind: .parakeetV2English,
                state: .failed,
                detail: "FluidAudio is not linked."
            )
            #endif
        }
        return cachedStatus
    }

    func prepareModel() async throws -> SpeechModelStatus {
        cachedStatus = SpeechModelStatus(
            kind: .parakeetV2English,
            state: .downloading,
            detail: "Downloading and compiling Parakeet with FluidAudio."
        )

        #if canImport(FluidAudio)
        do {
            _ = try await AsrModels.downloadAndLoad(version: .v2)
            cachedStatus = SpeechModelStatus(
                kind: .parakeetV2English,
                state: .ready,
                detail: "Parakeet v2 English is ready for command transcription."
            )
            hasProbed = true
            return cachedStatus
        } catch {
            cachedStatus = SpeechModelStatus(
                kind: .parakeetV2English,
                state: .failed,
                detail: "FluidAudio failed to prepare the model: \(error.localizedDescription)"
            )
            throw error
        }
        #else
        cachedStatus = SpeechModelStatus(
            kind: .parakeetV2English,
            state: .failed,
            detail: "FluidAudio is not linked yet. Add the Swift package before downloading models."
        )
        throw AnnaError.transcriptionUnavailable
        #endif
    }
}
