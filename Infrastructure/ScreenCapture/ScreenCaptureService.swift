import Foundation
import ScreenCaptureKit
import AppKit
import CoreGraphics

struct ScreenCaptureResult: Sendable {
    let base64PNG: String
    let widthPixels: Int
    let heightPixels: Int
    let displayWidthPoints: Int
    let displayHeightPoints: Int
}

@MainActor
final class ScreenCaptureService {

    var excludeAnnaWindow: Bool = false

    func captureScreen() async throws -> ScreenCaptureResult {
        guard CGPreflightScreenCaptureAccess() else {
            throw AnnaError.screenCaptureFailed("Screen Recording permission not granted.")
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let mainDisplay = content.displays.first else {
            throw AnnaError.screenCaptureFailed("No display found.")
        }

        guard let screen = NSScreen.main else {
            throw AnnaError.screenCaptureFailed("No main screen found.")
        }

        let displayWidthPoints = Int(screen.frame.width)
        let displayHeightPoints = Int(screen.frame.height)

        // Exclude only overlay windows (buddy cursor, response bubble) but keep the
        // main Anna window visible so Claude can see and click its UI during tours.
        let ownBundleID = Bundle.main.bundleIdentifier
        let overlayWindows = content.windows.filter { window in
            guard window.owningApplication?.bundleIdentifier == ownBundleID else { return false }
            // Always exclude overlay windows (empty title or fullscreen)
            let isOverlay = window.title?.isEmpty ?? true || window.frame.width >= CGFloat(mainDisplay.width)
            // When excludeAnnaWindow is true, also exclude the main Anna window
            return isOverlay || excludeAnnaWindow
        }

        let filter = SCContentFilter(display: mainDisplay, excludingWindows: overlayWindows)
        let config = SCStreamConfiguration()

        // Match Clicky's approach: 1280px max, preserve aspect ratio.
        // Smaller screenshots give Claude better coordinate accuracy.
        let maxDimension = 1280
        let aspectRatio = CGFloat(mainDisplay.width) / CGFloat(mainDisplay.height)
        if mainDisplay.width >= mainDisplay.height {
            config.width = maxDimension
            config.height = Int(CGFloat(maxDimension) / aspectRatio)
        } else {
            config.height = maxDimension
            config.width = Int(CGFloat(maxDimension) * aspectRatio)
        }
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        let actualWidth = image.width
        let actualHeight = image.height

        // Use JPEG for smaller payload — matches Clicky's approach
        guard let jpegData = NSBitmapImageRep(cgImage: image)
                .representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            throw AnnaError.screenCaptureFailed("Could not encode screenshot to JPEG.")
        }

        return ScreenCaptureResult(
            base64PNG: jpegData.base64EncodedString(),
            widthPixels: actualWidth,
            heightPixels: actualHeight,
            displayWidthPoints: displayWidthPoints,
            displayHeightPoints: displayHeightPoints
        )
    }

    func captureToFile() async throws -> (url: URL, widthPixels: Int, heightPixels: Int, displayWidthPoints: Int, displayHeightPoints: Int) {
        let result = try await captureScreen()
        guard let data = Data(base64Encoded: result.base64PNG) else {
            throw AnnaError.screenCaptureFailed("Invalid base64 data.")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("anna-screenshot-\(UUID().uuidString)")
            .appendingPathExtension("jpg")
        try data.write(to: url)
        return (url: url, widthPixels: result.widthPixels, heightPixels: result.heightPixels,
                displayWidthPoints: result.displayWidthPoints, displayHeightPoints: result.displayHeightPoints)
    }

    func mainScreenSize() -> CGSize {
        NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
    }
}
