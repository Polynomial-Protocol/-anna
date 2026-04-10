import AppKit
import ApplicationServices

/// Uses macOS Accessibility APIs to snap approximate screen coordinates to the
/// actual UI element at that position — giving pixel-perfect pointer accuracy.
///
/// Modeled after Clicky's ElementLocationDetector: Claude gives approximate coords
/// from the screenshot, we use AX to find the real element and its actual frame.
@MainActor
final class ElementLocationDetector {

    /// The result of element detection: the element's center in AppKit screen
    /// coordinates (bottom-left origin) and its full display frame.
    struct DetectedElement {
        let screenLocation: CGPoint   // center, AppKit coords (bottom-left origin)
        let displayFrame: CGRect      // full frame, AppKit coords
        let label: String?
    }

    /// Whether the app has Accessibility permission.
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Given approximate screenshot coordinates and the screenshot/display dimensions,
    /// finds the actual UI element at that position and returns its precise location.
    ///
    /// - Parameters:
    ///   - screenshotX: X coordinate in screenshot pixel space (top-left origin)
    ///   - screenshotY: Y coordinate in screenshot pixel space (top-left origin)
    ///   - screenshotWidth: Width of the screenshot in pixels
    ///   - screenshotHeight: Height of the screenshot in pixels
    ///   - label: Optional label from Claude describing the element
    /// - Returns: The detected element with its actual screen position, or nil.
    func detectElement(
        screenshotX: CGFloat,
        screenshotY: CGFloat,
        screenshotWidth: CGFloat,
        screenshotHeight: CGFloat,
        label: String?
    ) -> DetectedElement? {
        guard let screen = NSScreen.main else { return nil }
        guard hasAccessibilityPermission else { return nil }

        // Step 1: Convert screenshot coordinates to Quartz/CG screen coordinates.
        // Screenshot uses top-left origin, same as Quartz display coordinates.
        // We need to map from screenshot pixel space to display point space.
        let scaleX = screen.frame.width / screenshotWidth
        let scaleY = screen.frame.height / screenshotHeight

        // Quartz coordinates: origin at top-left of primary display, Y increases downward
        let quartzX = screenshotX * scaleX + screen.frame.origin.x
        let quartzY = screenshotY * scaleY

        // Step 2: Use AXUIElementCopyElementAtPosition to find the element.
        // The AX API uses Quartz screen coordinates (top-left origin).
        let systemWide = AXUIElementCreateSystemWide()
        var axElement: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(quartzX), Float(quartzY), &axElement)

        guard result == .success, let element = axElement else {
            // No element found — return nil so caller uses raw coordinates
            return nil
        }

        // Step 3: Get the element's actual position and size from AX.
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return nil
        }

        var axPosition = CGPoint.zero
        var axSize = CGSize.zero

        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &axPosition),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &axSize) else {
            return nil
        }

        // Skip elements that are too large (probably a window or the entire screen)
        // — we want specific buttons/labels/icons, not containers
        let maxReasonableSize: CGFloat = 400
        if axSize.width > maxReasonableSize && axSize.height > maxReasonableSize {
            // Try to get a child element at the same position instead
            if let child = findChildAtPosition(parent: element, quartzX: quartzX, quartzY: quartzY) {
                return child
            }
            // Still return the large element rather than nothing
        }

        // Step 4: Convert AX position (Quartz top-left origin) to AppKit (bottom-left origin).
        // For the primary screen: appKitY = screenHeight - quartzY
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let elementCenterQuartzX = axPosition.x + axSize.width / 2
        let elementCenterQuartzY = axPosition.y + axSize.height / 2

        let appKitX = elementCenterQuartzX
        let appKitY = primaryScreenHeight - elementCenterQuartzY

        // Build the display frame in AppKit coordinates
        let frameAppKitY = primaryScreenHeight - (axPosition.y + axSize.height)
        let displayFrame = CGRect(
            x: axPosition.x,
            y: frameAppKitY,
            width: axSize.width,
            height: axSize.height
        )

        // Try to get the element's label/title for verification
        var titleRef: CFTypeRef?
        var detectedLabel = label
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
           let title = titleRef as? String, !title.isEmpty {
            detectedLabel = title
        } else if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &titleRef) == .success,
                  let desc = titleRef as? String, !desc.isEmpty {
            detectedLabel = desc
        }

        return DetectedElement(
            screenLocation: CGPoint(x: appKitX, y: appKitY),
            displayFrame: displayFrame,
            label: detectedLabel ?? label
        )
    }

    // MARK: - Private

    /// If the element at the position is a large container, try to find a more specific child.
    private func findChildAtPosition(parent: AXUIElement, quartzX: CGFloat, quartzY: CGFloat) -> DetectedElement? {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 1080

        for child in children {
            var posRef: CFTypeRef?
            var sizeRef: CFTypeRef?

            guard AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &posRef) == .success,
                  AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &sizeRef) == .success else {
                continue
            }

            var pos = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetValue(posRef as! AXValue, .cgPoint, &pos),
                  AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else {
                continue
            }

            let frame = CGRect(origin: pos, size: size)
            if frame.contains(CGPoint(x: quartzX, y: quartzY)) && size.width < 400 && size.height < 400 {
                let centerQX = pos.x + size.width / 2
                let centerQY = pos.y + size.height / 2
                let appKitY = primaryScreenHeight - centerQY
                let frameAppKitY = primaryScreenHeight - (pos.y + size.height)

                var titleRef: CFTypeRef?
                var label: String? = nil
                if AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let title = titleRef as? String, !title.isEmpty {
                    label = title
                }

                return DetectedElement(
                    screenLocation: CGPoint(x: centerQX, y: appKitY),
                    displayFrame: CGRect(x: pos.x, y: frameAppKitY, width: size.width, height: size.height),
                    label: label
                )
            }
        }

        return nil
    }
}
