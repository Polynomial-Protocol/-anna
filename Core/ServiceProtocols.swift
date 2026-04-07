import Foundation

protocol PermissionService: AnyObject {
    func currentStatuses() -> [PermissionStatus]
    func refresh() -> [PermissionStatus]
    func request(_ kind: PermissionKind) async -> PermissionStatus
    func openSystemSettings(for kind: PermissionKind)
}

protocol AudioCaptureService: AnyObject {
    func beginCapture() async throws
    func finishCapture() async throws -> CapturedUtterance
    func cancelCapture() async
}

protocol VoiceTranscriptionService: AnyObject {
    func transcribe(_ utterance: CapturedUtterance) async throws -> TranscriptionResult
}

protocol SpeechModelService: AnyObject {
    func status() async -> SpeechModelStatus
    func prepareModel() async throws -> SpeechModelStatus
}

protocol TextInsertionService: AnyObject {
    func insertText(_ text: String) async throws
}
