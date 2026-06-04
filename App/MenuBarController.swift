import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let coordinator: CaptureCoordinator

    init(coordinator: CaptureCoordinator) {
        self.coordinator = coordinator
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder",
                                           accessibilityDescription: "BetterScreenshot")
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Capture Area", action: #selector(area), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Capture Window", action: #selector(window), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Capture Fullscreen", action: #selector(full), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Capture Text", action: #selector(captureText), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Pin from Clipboard", action: #selector(pinClipboard), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    @objc private func area() { coordinator.captureArea() }
    @objc private func window() { coordinator.captureFrontWindow() }
    @objc private func full() { coordinator.captureFullscreen() }
    @objc private func captureText() { coordinator.captureText() }
    @objc private func pinClipboard() { coordinator.pinFromClipboard() }
    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

extension MenuBarController: NSMenuItemValidation {
    nonisolated func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        MainActor.assumeIsolated {
            if menuItem.action == #selector(pinClipboard) { return coordinator.clipboardHasImage }
            return true
        }
    }
}
