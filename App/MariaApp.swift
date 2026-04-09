import SwiftUI
import AppKit

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

final class AnnaAppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AnnaAppDelegate?
    weak var container: AppContainer?
    private var statusItem: NSStatusItem?

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
            let image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Anna")
            image?.isTemplate = true  // Adapts to dark/light menu bar automatically
            button.image = image
            button.action = #selector(statusBarClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
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
        // Temporarily become regular app so windows activate properly
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
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
        // Check if all windows are closed/miniaturized
        let hasVisibleWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        if !hasVisibleWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
