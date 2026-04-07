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
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        CleanInstallHelper.performIfNeeded()
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
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Anna")
        }

        let menu = NSMenu()
        let info = NSMenuItem(title: "Right ⌘ Agent · Right ⌥ Dictation", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(NSMenuItem.separator())

        let openItem = NSMenuItem(title: "Open Anna...", action: #selector(showWindow), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Anna", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc func showWindow() {
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
