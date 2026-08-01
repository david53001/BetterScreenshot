import Foundation

/// Maps a monochrome auto-dismiss slider position to a persisted seconds value.
/// The slider runs over an ordered table of stops — 30s, 1m, 2m, 5m, 10m, 15m, 30m —
/// followed by a trailing "Never" stop that persists as 0.
public enum OverlayDismissScale {
    /// The finite stops, shortest first, in seconds. Slider position == index.
    public static let finiteStops = [30, 60, 120, 300, 600, 900, 1800]
    public static let neverSeconds = 0

    /// Slider position of the trailing "Never" stop (one past the last finite stop).
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

    /// Rounds a persisted value to the nearest stop, so a legacy value (e.g. the 6s
    /// default shipped before the 30s…30m scale) still resolves to a value the slider
    /// can show and the overlay can honour. Ties break toward the shorter stop.
    public static func snap(_ seconds: Int) -> Int {
        guard seconds > 0 else { return neverSeconds }
        return finiteStops.min(by: { abs($0 - seconds) < abs($1 - seconds) }) ?? finiteStops[0]
    }

    /// The "Never" stop shows as ∞ — it reads as "forever" at a glance and keeps the
    /// slider's value label narrow next to the numeric stops.
    public static let neverLabel = "∞"

    public static func label(_ seconds: Int) -> String {
        if seconds <= 0 { return neverLabel }
        return seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m"
    }
}
