import SwiftUI

@main
struct BetterScreenshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        // SettingsView is created in Task 12; use EmptyView until then so this task compiles.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    private var coordinator: CaptureCoordinator!
    private var menuBar: MenuBarController!
    private let hotKeys = HotKeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        coordinator = CaptureCoordinator(settings: settings)
        menuBar = MenuBarController(coordinator: coordinator)
        // Defaults: ⌘⇧4 area, ⌘⇧5 window, ⌘⇧6 fullscreen.
        hotKeys.register(key: "4", command: true, shift: true, option: false, control: false) {
            [weak self] in Task { @MainActor in self?.coordinator.captureArea() }
        }
        hotKeys.register(key: "5", command: true, shift: true, option: false, control: false) {
            [weak self] in Task { @MainActor in self?.coordinator.captureFrontWindow() }
        }
        hotKeys.register(key: "6", command: true, shift: true, option: false, control: false) {
            [weak self] in Task { @MainActor in self?.coordinator.captureFullscreen() }
        }
    }
}
