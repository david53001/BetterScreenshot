import CoreGraphics
import AppKit

enum PermissionManager {
    /// True if screen-recording permission is already granted.
    static var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system permission prompt (first call) — returns immediately.
    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Shown when permission is missing: explains and deep-links to System Settings.
    static func presentDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = "BetterScreenshot needs Screen Recording access to capture your screen. Enable it in System Settings → Privacy & Security → Screen Recording, then relaunch."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            NSWorkspace.shared.open(url)
        }
    }
}
