import SwiftUI
import AppKit
import Combine

@main
struct AnnaApp: App {
    @NSApplicationDelegateAdaptor(AnnaAppDelegate.self) var appDelegate
    @StateObject private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup("Anna") {
            RootContentView()
                .environmentObject(container)
                .frame(minWidth: 980, minHeight: 700)
                .task {
                    container.configureHotkeysIfNeeded()
                    AnnaAppDelegate.shared?.container = container
                    AnnaAppDelegate.shared?.setupStatusItem()
                }
        }
        .defaultSize(width: 980, height: 700)
        .commands {
            CommandMenu("Anna") {
                Button("Toggle Text Bar") {
                    container.textBarController.toggle(viewModel: container.assistantViewModel)
                }
                .keyboardShortcut(.space, modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class AnnaAppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AnnaAppDelegate?
    weak var container: AppContainer?
    private var statusItem: NSStatusItem?
    private var tipCardSubscription: AnyCancellable?
    private var tipIconPulseTimer: Timer?
    private var pulsePhase: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        CleanInstallHelper.performIfNeeded()

        // LSUIElement is set in Info.plist, so the app won't appear in the Dock.
        // We set .accessory policy to ensure correct behavior: no dock icon, has menu bar.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWindow() }
        return true
    }

    func setupStatusItem() {
        guard statusItem == nil else { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = statusImage(withPendingTip: false)
            button.action = #selector(statusBarClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Follow tip-card visibility so the icon gains a small dot badge and
        // gentle pulse whenever a tip is waiting for the user.
        tipCardSubscription = container?.tipCardController.$isVisible
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in
                self?.handleTipVisibilityChanged(visible)
            }
    }

    private func handleTipVisibilityChanged(_ visible: Bool) {
        tipIconPulseTimer?.invalidate()
        tipIconPulseTimer = nil
        pulsePhase = false
        statusItem?.button?.image = statusImage(withPendingTip: visible)
        guard visible else { return }
        tipIconPulseTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.pulsePhase.toggle()
            self.statusItem?.button?.image = self.statusImage(
                withPendingTip: true, muted: self.pulsePhase)
        }
    }

    /// Draws the status-bar icon, optionally with a colored dot badge at
    /// the bottom-right indicating a pending tip.
    private func statusImage(withPendingTip: Bool, muted: Bool = false) -> NSImage? {
        guard let base = NSImage(systemSymbolName: "waveform.circle",
                                 accessibilityDescription: "Anna") else { return nil }
        base.isTemplate = true
        guard withPendingTip else { return base }

        let size = NSSize(width: 18, height: 18)
        let composed = NSImage(size: size)
        composed.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: size),
                  from: .zero, operation: .sourceOver, fraction: 1.0)
        let dotSize: CGFloat = 7
        let dotRect = NSRect(
            x: size.width - dotSize - 0.5,
            y: 0.5,
            width: dotSize, height: dotSize)
        let color = NSColor.systemBlue.withAlphaComponent(muted ? 0.55 : 0.95)
        color.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
        composed.unlockFocus()
        composed.isTemplate = false // keep color fidelity for the dot
        return composed
    }

    @objc private func statusBarClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu(sender)
        } else {
            showWindow()
        }
    }

    private func showContextMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()

        // Status indicator
        let statusText = "Right \u{2318} Agent \u{00B7} Right \u{2325} Dictation"
        let info = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(NSMenuItem.separator())

        let openItem = NSMenuItem(title: "Open Anna\u{2026}", action: #selector(showWindow), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Anna", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        // Remove menu after it closes so left-click action works next time
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
        }
    }

    @objc func showWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Try to find and show an existing window
        for window in NSApp.windows {
            if window.canBecomeMain || window.title.contains("Anna") || window.contentView != nil {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                return
            }
        }

        // If no window found, open a new one via SwiftUI
        if #available(macOS 14.0, *) {
            // Force SwiftUI to create a new window instance
            NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - Window Close Observer

/// When all windows close, revert to accessory (menu-bar-only) mode so the dock icon disappears.
extension AnnaAppDelegate {
    func applicationDidResignActive(_ notification: Notification) {
        // Only revert to accessory mode if ALL main windows are truly closed (not just unfocused)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let hasVisibleWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain && !$0.isMiniaturized }
            if !hasVisibleWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
