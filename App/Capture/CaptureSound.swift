import AppKit

enum CaptureSound {
    /// Plays a short capture sound. Prefers the macOS screenshot sound if present, else a safe system sound.
    static func play() {
        let screenshotSound = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aif"
        if FileManager.default.fileExists(atPath: screenshotSound), let s = NSSound(contentsOfFile: screenshotSound, byReference: true) {
            s.play(); return
        }
        NSSound(named: "Tink")?.play()   // Tink is a guaranteed /System/Library/Sounds entry
    }
}
