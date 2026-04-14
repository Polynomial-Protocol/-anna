import Foundation
import AppKit
import ApplicationServices

/// Reads the frontmost app's UI state via the macOS Accessibility API.
///
/// Primary path: `AXUIElement` tree → compact JSON snapshot (< 4KB).
/// Fallback path: caller should switch to screenshot+vision when
/// `frontmostIsElectron()` returns true or the tree is empty.
///
/// Also exposes a first-launch counter keyed by bundle id so we know when
/// to trigger onboarding for an app the user has never opened before.
@MainActor
final class PerceptionEngine {

    struct AppInfo: Sendable {
        let bundleID: String
        let name: String
        let processID: pid_t
        let isElectron: Bool
        let launchCount: Int     // post-increment value; 1 == first ever open
    }

    struct UINode: Sendable, Codable {
        let role: String
        let title: String?
        let value: String?
        let description: String?
        let x: Double?
        let y: Double?
        let w: Double?
        let h: Double?
        let focused: Bool?
        let enabled: Bool?
        let children: [UINode]
    }

    struct Snapshot: Sendable {
        let app: AppInfo
        let tree: UINode?          // nil if AX tree was empty (Electron / not trusted)
        let compactJSON: String    // bounded ≤ ~4KB
        let sizeBytes: Int
    }

    // Known Electron apps — AX tree is either empty or unusably sparse.
    // Extend this list as new ones appear.
    private static let electronBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.tinyspeck.slackmacgap",
        "com.figma.Desktop",
        "com.figma.FigJam",
        "com.hnc.Discord",
        "com.hnc.DiscordCanary",
        "com.hnc.DiscordPTB",
        "notion.id",
        "com.notion.Notion",
        "com.linear",
        "com.spotify.client",
        "com.github.GitHubClient",
        "com.postmanlabs.mac",
        "com.electron.cursor",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.exafunction.windsurf",
    ]

    private let maxDepth = 5
    private let maxBytes = 4096
    private let maxChildrenPerNode = 40

    /// We only show the macOS AX permission dialog once per app session —
    /// after that the user has either granted it or will resolve it in
    /// System Settings. Re-prompting on every snapshot would flood the UI.
    private var accessibilityPromptShown = false

    // MARK: - Frontmost app + first-launch tracking

    func frontmostApp() -> AppInfo? {
        guard let running = NSWorkspace.shared.frontmostApplication,
              let bundleID = running.bundleIdentifier else { return nil }
        let name = running.localizedName ?? bundleID
        let count = bumpLaunchCounter(bundleID: bundleID)
        return AppInfo(
            bundleID: bundleID,
            name: name,
            processID: running.processIdentifier,
            isElectron: Self.electronBundleIDs.contains(bundleID),
            launchCount: count
        )
    }

    /// Returns the *new* launch count (1 on very first observation).
    /// Backed by UserDefaults — tiny, survives app updates.
    private func bumpLaunchCounter(bundleID: String) -> Int {
        let key = "anna.launchCount.\(bundleID)"
        let next = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(next, forKey: key)
        return next
    }

    func isFirstObservation(of bundleID: String) -> Bool {
        UserDefaults.standard.integer(forKey: "anna.launchCount.\(bundleID)") <= 1
    }

    // MARK: - Snapshot

    func snapshotFrontmost() -> Snapshot? {
        guard let app = frontmostApp() else { return nil }
        guard AXIsProcessTrusted() else {
            // No Accessibility permission yet. Prompt once — subsequent calls
            // stay silent so we don't spam the user. Dialog is asynchronous;
            // this call still returns empty, but next snapshot will work.
            if !accessibilityPromptShown {
                accessibilityPromptShown = true
                let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(opts)
            }
            return Snapshot(app: app, tree: nil, compactJSON: "{}", sizeBytes: 2)
        }
        if app.isElectron {
            // Skip the tree walk — caller should use screenshot + vision.
            return Snapshot(app: app, tree: nil, compactJSON: "{}", sizeBytes: 2)
        }

        let axApp = AXUIElementCreateApplication(app.processID)
        let tree = readTree(axApp, depth: 0)

        // Serialize + budget-clip to 4KB.
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        var data = (try? encoder.encode(tree)) ?? Data("{}".utf8)
        if data.count > maxBytes, let trimmed = trim(tree: tree, toBudget: maxBytes) {
            data = (try? encoder.encode(trimmed)) ?? data
        }
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return Snapshot(app: app, tree: tree, compactJSON: json, sizeBytes: data.count)
    }

    // MARK: - AX walk

    private func readTree(_ element: AXUIElement, depth: Int) -> UINode {
        let role = copyString(element, kAXRoleAttribute as CFString) ?? ""
        let title = copyString(element, kAXTitleAttribute as CFString)
        let value = copyString(element, kAXValueAttribute as CFString)
        let desc = copyString(element, kAXDescriptionAttribute as CFString)
        let focused = copyBool(element, kAXFocusedAttribute as CFString)
        let enabled = copyBool(element, kAXEnabledAttribute as CFString)
        let (x, y) = copyPoint(element, kAXPositionAttribute as CFString)
        let (w, h) = copySize(element, kAXSizeAttribute as CFString)

        var kids: [UINode] = []
        if depth < maxDepth {
            if let children = copyArray(element, kAXChildrenAttribute as CFString) {
                for child in children.prefix(maxChildrenPerNode) {
                    let axChild = child as! AXUIElement
                    let node = readTree(axChild, depth: depth + 1)
                    if Self.shouldKeep(node, depth: depth + 1) {
                        kids.append(node)
                    }
                }
            }
        }

        return UINode(
            role: role,
            title: title?.trimmingOrNil,
            value: value?.trimmingOrNil?.prefixed(120),
            description: desc?.trimmingOrNil?.prefixed(120),
            x: x, y: y, w: w, h: h,
            focused: focused,
            enabled: enabled,
            children: kids
        )
    }

    /// Prune uninteresting leaves: below max depth, only keep nodes that
    /// carry semantic signal (interactive, focused, or have a title).
    private static func shouldKeep(_ node: UINode, depth: Int) -> Bool {
        if depth <= 3 { return true }
        if node.focused == true { return true }
        if let title = node.title, !title.isEmpty { return true }
        if interactiveRoles.contains(node.role) { return true }
        return !node.children.isEmpty
    }

    private static let interactiveRoles: Set<String> = [
        "AXButton", "AXTextField", "AXTextArea", "AXPopUpButton",
        "AXCheckBox", "AXRadioButton", "AXLink", "AXMenuItem",
        "AXMenuBarItem", "AXTab", "AXSlider", "AXComboBox"
    ]

    /// Progressive budget trim: drop the deepest children until we fit.
    private func trim(tree: UINode, toBudget budget: Int) -> UINode? {
        var current = tree
        var maxKeep = maxDepth
        while maxKeep > 1 {
            maxKeep -= 1
            current = Self.truncate(node: tree, maxDepth: maxKeep)
            let encoded = (try? JSONEncoder().encode(current)) ?? Data()
            if encoded.count <= budget { return current }
        }
        return current
    }

    private static func truncate(node: UINode, maxDepth: Int) -> UINode {
        guard maxDepth > 0 else {
            return UINode(role: node.role, title: node.title, value: node.value,
                          description: node.description, x: node.x, y: node.y,
                          w: node.w, h: node.h, focused: node.focused,
                          enabled: node.enabled, children: [])
        }
        return UINode(
            role: node.role, title: node.title, value: node.value,
            description: node.description, x: node.x, y: node.y,
            w: node.w, h: node.h, focused: node.focused, enabled: node.enabled,
            children: node.children.map { truncate(node: $0, maxDepth: maxDepth - 1) }
        )
    }

    // MARK: - AX attribute helpers

    private func copyString(_ element: AXUIElement, _ attr: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr, &value) == .success,
              let s = value as? String else { return nil }
        return s
    }

    private func copyBool(_ element: AXUIElement, _ attr: CFString) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr, &value) == .success,
              let n = value as? NSNumber else { return nil }
        return n.boolValue
    }

    private func copyArray(_ element: AXUIElement, _ attr: CFString) -> [CFTypeRef]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr, &value) == .success,
              let arr = value as? [CFTypeRef] else { return nil }
        return arr
    }

    private func copyPoint(_ element: AXUIElement, _ attr: CFString) -> (Double?, Double?) {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr, &value) == .success else { return (nil, nil) }
        let axVal = value as! AXValue
        var p = CGPoint.zero
        guard AXValueGetType(axVal) == .cgPoint, AXValueGetValue(axVal, .cgPoint, &p) else { return (nil, nil) }
        return (p.x, p.y)
    }

    private func copySize(_ element: AXUIElement, _ attr: CFString) -> (Double?, Double?) {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr, &value) == .success else { return (nil, nil) }
        let axVal = value as! AXValue
        var s = CGSize.zero
        guard AXValueGetType(axVal) == .cgSize, AXValueGetValue(axVal, .cgSize, &s) else { return (nil, nil) }
        return (s.width, s.height)
    }
}

// MARK: - Small string helpers

private extension String {
    var trimmingOrNil: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
    func prefixed(_ n: Int) -> String {
        count <= n ? self : String(prefix(n)) + "…"
    }
}
