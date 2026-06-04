import Foundation
import CaptureKit
import RecordingKit

final class SettingsStore: ObservableObject {
    @Published var settings: CaptureSettings
    @Published var saveDirectory: URL
    @Published var bindings: HotkeyBindings
    /// Actions whose combo macOS refused to register (not persisted).
    @Published var failedActions: Set<HotkeyAction> = []
    @Published var recording: RecordingConfig

    private let defaults = UserDefaults.standard

    init() {
        let dict = defaults.dictionary(forKey: "captureSettings") as? [String: String] ?? [:]
        self.settings = dict.isEmpty ? .default : CaptureSettings(dictionary: dict)
        if let saved = defaults.url(forKey: "saveDirectory") {
            self.saveDirectory = saved
        } else {
            // Default to wherever macOS screenshots normally go (the
            // com.apple.screencapture `location`), falling back to ~/Desktop.
            self.saveDirectory = SettingsStore.systemScreenshotLocation()
        }
        if let dict = defaults.dictionary(forKey: "hotkeyBindings") as? [String: String] {
            self.bindings = HotkeyBindings(dictionary: dict)
        } else {
            self.bindings = .defaults
        }
        let recDict = defaults.dictionary(forKey: "recordingConfig") as? [String: String] ?? [:]
        self.recording = recDict.isEmpty ? .default : RecordingConfig(dictionary: recDict)
    }

    func persist() {
        defaults.set(settings.dictionary, forKey: "captureSettings")
        defaults.set(saveDirectory, forKey: "saveDirectory")
        defaults.set(bindings.dictionary, forKey: "hotkeyBindings")
        defaults.set(recording.dictionary, forKey: "recordingConfig")
    }

    /// The user's macOS screenshot folder, or ~/Desktop if it isn't customized.
    static func systemScreenshotLocation() -> URL {
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
        guard let raw = UserDefaults(suiteName: "com.apple.screencapture")?
                .string(forKey: "location"), !raw.isEmpty else { return desktop }
        let path = (raw as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
              isDir.boolValue else { return desktop }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
