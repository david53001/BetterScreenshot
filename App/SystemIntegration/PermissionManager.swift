import CoreGraphics
import AppKit

enum PermissionManager {
    /// True if screen-recording permission is already granted.
    static var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system permission prompt (first call ever) — returns immediately.
    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Deep-link straight to Privacy & Security → Screen Recording.
    static func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// Screen-recording grants only take effect at process start, so the
    /// onboarding flow relaunches the app once the permission lands. Plain
    /// `open` (no -n) just activates if a new instance is already starting,
    /// avoiding duplicates when macOS's own "Quit & Reopen" raced us.
    static func relaunchApp() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The bundle path is passed as $0 — never interpolated into the command
        // string — so quotes/metacharacters in the install path can't break it.
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}
