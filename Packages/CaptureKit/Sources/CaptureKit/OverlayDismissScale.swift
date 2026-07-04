import Foundation

/// Maps a monochrome auto-dismiss slider position to a persisted seconds value.
/// Positions 2...30 are that many seconds; position >= NeverPosition means "Never" (persisted as 0).
public enum OverlayDismissScale {
    public static let minSeconds = 2
    public static let maxSeconds = 30
    public static let neverSeconds = 0
    public static let neverPosition = 31

    public static func positionToSeconds(_ position: Int) -> Int {
        if position >= neverPosition { return neverSeconds }
        return min(max(position, minSeconds), maxSeconds)
    }

    public static func secondsToPosition(_ seconds: Int) -> Int {
        if seconds <= 0 { return neverPosition }
        return min(max(seconds, minSeconds), maxSeconds)
    }

    public static func label(_ seconds: Int) -> String {
        seconds <= 0 ? "Never" : "\(seconds)s"
    }
}
