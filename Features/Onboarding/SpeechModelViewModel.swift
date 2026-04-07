import SwiftUI

@MainActor
final class SpeechModelViewModel: ObservableObject {
    @Published var status: SpeechModelStatus

    private let service: SpeechModelService

    init(service: SpeechModelService) {
        self.service = service
        self.status = SpeechModelStatus(
            kind: .parakeetV2English,
            state: .notInstalled,
            detail: "Checking model state..."
        )
        Task { await refresh() }
    }

    func refresh() async {
        status = await service.status()
    }

    func download() {
        Task {
            do {
                status = SpeechModelStatus(
                    kind: .parakeetV2English,
                    state: .downloading,
                    detail: "Preparing Parakeet model..."
                )
                let updated = try await service.prepareModel()
                await MainActor.run {
                    self.status = updated
                }
            } catch {
                await MainActor.run {
                    self.status = SpeechModelStatus(
                        kind: .parakeetV2English,
                        state: .failed,
                        detail: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                }
            }
        }
    }
}
