import Foundation
import CaptureKit

final class SettingsStore: ObservableObject {
    @Published var settings: CaptureSettings
    @Published var saveDirectory: URL

    private let defaults = UserDefaults.standard

    init() {
        let dict = defaults.dictionary(forKey: "captureSettings") as? [String: String] ?? [:]
        self.settings = dict.isEmpty ? .default : CaptureSettings(dictionary: dict)
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let saved = defaults.url(forKey: "saveDirectory") {
            self.saveDirectory = saved
        } else {
            self.saveDirectory = home.appendingPathComponent("Desktop")
        }
    }

    func persist() {
        defaults.set(settings.dictionary, forKey: "captureSettings")
        defaults.set(saveDirectory, forKey: "saveDirectory")
    }
}
