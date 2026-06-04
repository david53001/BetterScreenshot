import Foundation
import ServiceManagement

/// "Launch at login" via SMAppService (the modern Login Items API).
/// SMAppService is the source of truth — no mirrored flag in UserDefaults —
/// so the Settings toggle stays correct even when the user flips it in
/// System Settings → General → Login Items instead.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("LaunchAtLogin: failed to \(enabled ? "register" : "unregister"): \(error)")
        }
    }
}
