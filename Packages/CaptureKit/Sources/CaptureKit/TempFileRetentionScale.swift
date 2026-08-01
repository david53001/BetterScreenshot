import Foundation

/// Maps the Settings "Keep cached files for" slider position to the persisted seconds value
/// behind `CaptureSettings.tempRetentionSeconds` — how long the temporary PNG the app writes
/// for a drag-out or for the clipboard's file path lives in the system temp directory before
/// it is deleted. Those files sit in `BetterScreenshot-<UUID>/` folders under `$TMPDIR`, e.g.
/// `/var/folders/…/T/BetterScreenshot-4C7446B4-…/Screenshot 2026-08-01 at 18.25.57.png`.
///
/// The slider runs over an ordered table of stops — 10s, 30s, 5m, 10m, 30m, 1h — followed by
/// a trailing stop that persists as 0 and means "keep those files forever".
/// A slider position is a stop *index*, not a second count.
public enum TempFileRetentionScale {
    /// The finite stops, shortest first, in seconds. Slider position == index.
    public static let finiteStops = [10, 30, 300, 600, 1800, 3600]
    public static let neverSeconds = 0

    /// Slider position of the trailing "keep forever" stop (one past the last finite stop).
    public static var neverPosition: Int { finiteStops.count }
    public static let minPosition = 0

    public static func positionToSeconds(_ position: Int) -> Int {
        if position >= neverPosition { return neverSeconds }
        return finiteStops[max(position, minPosition)]
    }

    public static func secondsToPosition(_ seconds: Int) -> Int {
        guard seconds > 0 else { return neverPosition }
        return finiteStops.firstIndex(of: snap(seconds)) ?? neverPosition
    }

    /// Rounds a persisted value to the nearest stop, so a value written by another build
    /// still resolves to a stop the slider can show. Ties break toward the shorter stop.
    public static func snap(_ seconds: Int) -> Int {
        guard seconds > 0 else { return neverSeconds }
        return finiteStops.min(by: { abs($0 - seconds) < abs($1 - seconds) }) ?? finiteStops[0]
    }

    /// The age cutoff to hand `TempImageWriter.cleanExpired(in:olderThan:now:)`.
    /// `nil` means the ∞ stop — never delete the temp files.
    public static func maxAge(forSeconds seconds: Int) -> TimeInterval? {
        seconds > 0 ? TimeInterval(seconds) : nil
    }

    /// The "keep forever" stop shows as ∞ — matches the Quick Access auto-dismiss slider.
    public static let neverLabel = "∞"

    public static func label(_ seconds: Int) -> String {
        if seconds <= 0 { return neverLabel }
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }
}
