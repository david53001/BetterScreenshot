import AppKit
import CaptureKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let coordinator: CaptureCoordinator
    private let settingsWindow: SettingsWindowController

    init(coordinator: CaptureCoordinator, settingsWindow: SettingsWindowController) {
        self.coordinator = coordinator
        self.settingsWindow = settingsWindow
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder",
                                           accessibilityDescription: "BetterScreenshot")
        buildMenu()
    }

    private var actionItems: [HotkeyAction: NSMenuItem] = [:]

    private func buildMenu() {
        let menu = NSMenu()
        func add(_ title: String, _ sel: Selector, _ action: HotkeyAction?) {
            let item = menu.addItem(withTitle: title, action: sel, keyEquivalent: "")
            item.target = self
            if let action { actionItems[action] = item }
        }
        add("Capture Area", #selector(area), .captureArea)
        add("Capture Window", #selector(window), .captureWindow)
        add("Capture Fullscreen", #selector(full), .captureFullscreen)
        add("Capture Text", #selector(captureText), .captureText)
        menu.addItem(.separator())
        add("Pin from Clipboard", #selector(pinClipboard), .pinFromClipboard)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    /// Display-only: firing stays Carbon. Menus just show the current combos.
    func refreshKeyEquivalents(_ bindings: HotkeyBindings) {
        for (action, item) in actionItems {
            if let combo = bindings.combo(for: action) {
                item.keyEquivalent = combo.keyEquivalent
                item.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue: combo.cocoaModifierFlags)
            } else {
                item.keyEquivalent = ""
                item.keyEquivalentModifierMask = []
            }
        }
    }

    @objc private func area() { coordinator.captureArea() }
    @objc private func window() { coordinator.captureFrontWindow() }
    @objc private func full() { coordinator.captureFullscreen() }
    @objc private func captureText() { coordinator.captureText() }
    @objc private func pinClipboard() { coordinator.pinFromClipboard() }
    @objc private func openSettings() {
        settingsWindow.show()
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
