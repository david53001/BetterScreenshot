import AppKit
import SwiftUI

/// Owns the single Settings window. Replaces the SwiftUI `Settings` scene, whose
/// private `showSettingsWindow:` opener silently broke on macOS 14 for
/// LSUIElement apps.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(store: store))
            let w = NSWindow(contentViewController: hosting)
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.title = "Settings"
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
    }
}
