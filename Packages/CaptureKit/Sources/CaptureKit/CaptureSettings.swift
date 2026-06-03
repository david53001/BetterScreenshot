import Foundation

public enum AfterCaptureBehavior: String, Equatable {
    case copyOnly, saveOnly, copyAndSave
}

public enum SettingsImageFormat: String, Equatable {
    case png, jpg
}

public struct CaptureSettings: Equatable {
    public var afterCapture: AfterCaptureBehavior
    public var format: SettingsImageFormat

    public static let `default` = CaptureSettings(afterCapture: .copyAndSave, format: .png)

    public var dictionary: [String: String] {
        ["afterCapture": afterCapture.rawValue, "format": format.rawValue]
    }

    public init(afterCapture: AfterCaptureBehavior, format: SettingsImageFormat) {
        self.afterCapture = afterCapture
        self.format = format
    }

    public init(dictionary: [String: String]) {
        self.afterCapture = AfterCaptureBehavior(rawValue: dictionary["afterCapture"] ?? "")
            ?? CaptureSettings.default.afterCapture
        self.format = SettingsImageFormat(rawValue: dictionary["format"] ?? "")
            ?? CaptureSettings.default.format
    }
}
