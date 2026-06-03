import Foundation

/// Disables/restores the native macOS ⌘⇧4 ("save picture of selected area as a file")
/// shortcut so it doesn't fire alongside BetterScreenshot's own ⌘⇧4 hotkey. Edits the
/// user-level `com.apple.symbolichotkeys` domain (symbolic-hotkey id 30) and reloads via
/// the private `activateSettings` helper so the change applies without a logout.
enum SystemScreenshotShortcuts {
    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let topKey = "AppleSymbolicHotKeys" as CFString
    /// id 30 = "Save picture of selected area as a file" = native ⌘⇧4.
    private static let areaScreenshotID = "30"

    /// Disable native ⌘⇧4 by writing the standard ⌘⇧4 binding with `enabled = 0`.
    static func disableNativeAreaScreenshot() {
        var hotKeys = currentHotKeys()
        hotKeys[areaScreenshotID] = [
            "enabled": 0,
            "value": [
                "parameters": [52, 21, 1_179_648], // ASCII '4', keycode 21, ⌘⇧ mask
                "type": "standard",
            ],
        ]
        write(hotKeys)
        reload()
    }

    /// Restore native ⌘⇧4 by removing our entry, reverting id 30 to its macOS default
    /// (enabled). Safe across crashes: "restore" always means "revert to default", so a
    /// run that was killed before this ran simply gets re-disabled on the next launch.
    static func restoreNativeAreaScreenshot() {
        var hotKeys = currentHotKeys()
        guard hotKeys[areaScreenshotID] != nil else { return }
        hotKeys.removeValue(forKey: areaScreenshotID)
        write(hotKeys)
        reload()
    }

    // MARK: - Preferences I/O

    private static func currentHotKeys() -> [String: Any] {
        let value = CFPreferencesCopyValue(topKey, domain,
                                           kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return (value as? [String: Any]) ?? [:]
    }

    private static func write(_ hotKeys: [String: Any]) {
        CFPreferencesSetValue(topKey, hotKeys as CFDictionary, domain,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    /// Reload symbolic hotkeys without a logout via the private SystemAdministration helper.
    private static func reload() {
        let helper = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
        guard FileManager.default.isExecutableFile(atPath: helper) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: helper)
        process.arguments = ["-u"]
        try? process.run()
        process.waitUntilExit()
    }
}
