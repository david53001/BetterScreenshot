import AppKit
import SwiftUI

/// Owns the single Settings window. Replaces the SwiftUI `Settings` scene, whose
/// private `showSettingsWindow:` opener silently broke on macOS 14 for
/// LSUIElement apps.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let store: SettingsStore
    private let shortcuts: ShortcutActions
    private let clearHistory: () -> Void

    init(store: SettingsStore, shortcuts: ShortcutActions, clearHistory: @escaping () -> Void) {
        self.store = store
        self.shortcuts = shortcuts
        self.clearHistory = clearHistory
    }

    func show() {
        if window == nil {
            let view = SettingsView(store: store, shortcuts: shortcuts, clearHistory: clearHistory)
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.title = "Settings"
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)   // ★ after makeKey, matching OnboardingController
    }
}
