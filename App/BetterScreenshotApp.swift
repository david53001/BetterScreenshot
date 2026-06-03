import SwiftUI

@main
struct BetterScreenshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        // No window scene: this is a menu-bar agent. Settings window added later.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // belt-and-suspenders with LSUIElement
        NSLog("BetterScreenshot launched")
    }
}
