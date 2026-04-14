import Foundation
import AppKit

/// Controls system-wide media playback via the private MediaRemote framework.
/// Used to pause music/video when Anna starts listening so mic capture isn't contaminated.
@MainActor
enum MediaController {

    // MARK: - MediaRemote command constants
    // From the private MediaRemote framework header.
    private static let kMRPlay: Int32 = 0
    private static let kMRPause: Int32 = 1
    private static let kMRTogglePlayPause: Int32 = 2

    private typealias MRSendCommand = @convention(c) (Int32, [AnyHashable: Any]?) -> Bool
    private typealias MRGetNowPlayingInfo = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void

    private static var mediaRemoteBundle: CFBundle? = {
        CFBundleCreate(kCFAllocatorDefault,
                       NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework"))
    }()

    // MARK: - Public API

    /// Returns true if any media is currently playing.
    static func isPlaying() async -> Bool {
        guard let bundle = mediaRemoteBundle,
              let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString)
        else { return false }

        let getInfo = unsafeBitCast(ptr, to: MRGetNowPlayingInfo.self)
        return await withCheckedContinuation { continuation in
            getInfo(DispatchQueue.main) { info in
                let rate = (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double) ?? 0
                continuation.resume(returning: rate > 0)
            }
        }
    }

    /// Pauses any currently playing media. Returns true if a pause was sent.
    @discardableResult
    static func pauseIfPlaying() async -> Bool {
        guard await isPlaying() else { return false }
        return sendCommand(kMRPause)
    }

    /// Resumes playback.
    @discardableResult
    static func resume() -> Bool {
        sendCommand(kMRPlay)
    }

    // MARK: - Internal

    private static func sendCommand(_ command: Int32) -> Bool {
        guard let bundle = mediaRemoteBundle,
              let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString)
        else { return false }

        let send = unsafeBitCast(ptr, to: MRSendCommand.self)
        return send(command, nil)
    }
}
