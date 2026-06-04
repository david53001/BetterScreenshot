import AppKit

// Plain AppKit lifecycle. The SwiftUI App existed only for its Settings scene,
// whose opener (private showSettingsWindow: selector) macOS 14 broke for
// LSUIElement apps — SettingsWindowController owns the window instead.
@main
@MainActor
enum Main {
    static func main() {
        let delegate = AppDelegate()
        NSApplication.shared.delegate = delegate
        NSApplication.shared.run()
    }
}
