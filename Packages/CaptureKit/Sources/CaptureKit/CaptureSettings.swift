import Foundation

public enum AfterCaptureBehavior: String, Equatable, CaseIterable {
    case copyOnly, saveOnly, copyAndSave, showOverlay
}

public enum SettingsImageFormat: String, Equatable, CaseIterable {
    case png, jpg
}

public enum OverlayCorner: String, Equatable, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

public struct CaptureSettings: Equatable {
    public var afterCapture: AfterCaptureBehavior
    public var format: SettingsImageFormat
    public var overlayCorner: OverlayCorner
    public var overlayAutoDismissSeconds: Int
    public var pinCornerRadius: Int
    public var pinShadow: Bool
    public var historyEnabled: Bool
    public var historyCap: Int
    /// How long a captured screenshot stays in the local cache before its
    /// cached copy + thumbnail are deleted. 0 == Never (keep until the cap evicts it).
    public var historyRetentionSeconds: Int
    public var playSound: Bool

    public static let `default` = CaptureSettings(
        afterCapture: .showOverlay, format: .png,
        overlayCorner: .bottomRight, overlayAutoDismissSeconds: 0)

    public var dictionary: [String: String] {
        ["afterCapture": afterCapture.rawValue,
         "format": format.rawValue,
         "overlayCorner": overlayCorner.rawValue,
         "overlayAutoDismissSeconds": String(overlayAutoDismissSeconds),
         "pinCornerRadius": String(pinCornerRadius),
         "pinShadow": pinShadow ? "true" : "false",
         "historyEnabled": historyEnabled ? "true" : "false",
         "historyCap": String(historyCap),
         "historyRetentionSeconds": String(historyRetentionSeconds),
         "playSound": playSound ? "1" : "0"]
    }

    public init(afterCapture: AfterCaptureBehavior, format: SettingsImageFormat,
                overlayCorner: OverlayCorner, overlayAutoDismissSeconds: Int,
                pinCornerRadius: Int = 8, pinShadow: Bool = true,
                historyEnabled: Bool = true, historyCap: Int = 50,
                historyRetentionSeconds: Int = 1800,
                playSound: Bool = true) {
        self.afterCapture = afterCapture
        self.format = format
        self.overlayCorner = overlayCorner
        self.overlayAutoDismissSeconds = overlayAutoDismissSeconds
        self.pinCornerRadius = pinCornerRadius
        self.pinShadow = pinShadow
        self.historyEnabled = historyEnabled
        self.historyCap = historyCap
        self.historyRetentionSeconds = historyRetentionSeconds
        self.playSound = playSound
    }

    public init(dictionary: [String: String]) {
        let d = CaptureSettings.default
        self.afterCapture = AfterCaptureBehavior(rawValue: dictionary["afterCapture"] ?? "") ?? d.afterCapture
        self.format = SettingsImageFormat(rawValue: dictionary["format"] ?? "") ?? d.format
        self.overlayCorner = OverlayCorner(rawValue: dictionary["overlayCorner"] ?? "") ?? d.overlayCorner
        let rawAutoDismiss = Int(dictionary["overlayAutoDismissSeconds"] ?? "") ?? d.overlayAutoDismissSeconds
        // Snap to the slider's stop table so a legacy persisted value (e.g. an older
        // build's 6s default) resolves to a stop the Settings slider can show.
        self.overlayAutoDismissSeconds = OverlayDismissScale.snap(rawAutoDismiss)
        self.pinCornerRadius = Int(dictionary["pinCornerRadius"] ?? "") ?? d.pinCornerRadius
        self.pinShadow = dictionary["pinShadow"].map { $0 == "true" } ?? d.pinShadow
        self.historyEnabled = dictionary["historyEnabled"].map { $0 == "true" } ?? d.historyEnabled
        let rawHistoryCap = Int(dictionary["historyCap"] ?? "") ?? d.historyCap
        // Snap to the allowed option set so a legacy persisted value (e.g. an
        // older build's default of 200) still resolves to a value the
        // Settings UI's 10/50/100 control can show as selected.
        self.historyCap = [10, 50, 100].min(by: { abs($0 - rawHistoryCap) < abs($1 - rawHistoryCap) }) ?? 50
        let rawRetention = Int(dictionary["historyRetentionSeconds"] ?? "") ?? d.historyRetentionSeconds
        // Snap to the slider's stop table, same as overlayAutoDismissSeconds above.
        self.historyRetentionSeconds = HistoryRetentionScale.snap(rawRetention)
        self.playSound = (dictionary["playSound"] ?? "1") != "0"
    }
}
