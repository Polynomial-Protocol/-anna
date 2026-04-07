import Foundation
import ScreenCaptureKit
import AppKit
import CoreGraphics

/// Captures the current screen content using ScreenCaptureKit.
/// Used to give Claude CLI visual context about what the user is looking at.
@MainActor
final class ScreenCaptureService {

    /// Captures the main display and returns a base64-encoded PNG string.
    func captureScreen() async throws -> String {
        guard CGPreflightScreenCaptureAccess() else {
            throw AnnaError.screenCaptureFailed("Screen Recording permission not granted.")
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let mainDisplay = content.displays.first else {
            throw AnnaError.screenCaptureFailed("No display found.")
        }

        let filter = SCContentFilter(display: mainDisplay, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = min(Int(mainDisplay.width), 1920)
        config.height = min(Int(mainDisplay.height), 1080)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))

        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [.compressionFactor: 0.8]) else {
            throw AnnaError.screenCaptureFailed("Could not encode screenshot to PNG.")
        }

        return pngData.base64EncodedString()
    }

    /// Captures and saves to a temp file, returns the file path.
    func captureToFile() async throws -> URL {
        let base64 = try await captureScreen()
        guard let data = Data(base64Encoded: base64) else {
            throw AnnaError.screenCaptureFailed("Invalid base64 data.")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("anna-screenshot-\(UUID().uuidString)")
            .appendingPathExtension("png")
        try data.write(to: url)
        return url
    }

    /// Returns the screen dimensions of the main display.
    func mainScreenSize() -> CGSize {
        NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
    }
}
