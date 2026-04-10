import Foundation
import ScreenCaptureKit
import AppKit
import CoreGraphics

/// Result of a screen capture, including the image data and its pixel dimensions.
struct ScreenCaptureResult: Sendable {
    let base64PNG: String
    let widthPixels: Int
    let heightPixels: Int
}

/// Captures the current screen content using ScreenCaptureKit.
/// Used to give Claude visual context about what the user is looking at.
@MainActor
final class ScreenCaptureService {

    /// Captures the main display and returns base64 PNG with actual pixel dimensions.
    func captureScreen() async throws -> ScreenCaptureResult {
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

        // Use the actual CGImage pixel dimensions — these are ground truth
        let actualWidth = image.width
        let actualHeight = image.height

        let nsImage = NSImage(cgImage: image, size: NSSize(width: actualWidth, height: actualHeight))

        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [.compressionFactor: 0.8]) else {
            throw AnnaError.screenCaptureFailed("Could not encode screenshot to PNG.")
        }

        return ScreenCaptureResult(
            base64PNG: pngData.base64EncodedString(),
            widthPixels: actualWidth,
            heightPixels: actualHeight
        )
    }

    /// Captures and saves to a temp file, returns the file URL and pixel dimensions.
    func captureToFile() async throws -> (url: URL, widthPixels: Int, heightPixels: Int) {
        let result = try await captureScreen()
        guard let data = Data(base64Encoded: result.base64PNG) else {
            throw AnnaError.screenCaptureFailed("Invalid base64 data.")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("anna-screenshot-\(UUID().uuidString)")
            .appendingPathExtension("png")
        try data.write(to: url)
        return (url: url, widthPixels: result.widthPixels, heightPixels: result.heightPixels)
    }

    /// Returns the screen dimensions of the main display.
    func mainScreenSize() -> CGSize {
        NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
    }
}
