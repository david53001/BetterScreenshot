namespace BetterScreenshot.Capture;

/// <summary>
/// Maps between the Quick Access "Auto-dismiss after" slider position and the persisted
/// <see cref="CaptureSettings.OverlayAutoDismissSeconds"/> value.
///
/// The slider runs over an ordered table of stops — 30s, 1m, 2m, 5m, 10m, 15m, 30m — followed by a
/// trailing "Never" stop that persists as <see cref="NeverSeconds"/> (0), which the overlay already
/// treats as "stay on screen until the user closes it" (see <c>QuickAccessWindow.StartAutoDismiss</c>).
/// A slider position is a stop <i>index</i>, not a second count. Keeping this mapping in one pure,
/// testable place means the Settings slider and the persisted int can never drift apart.
///
/// Mirrors the macOS <c>OverlayDismissScale</c>
/// (<c>Packages/CaptureKit/Sources/CaptureKit/OverlayDismissScale.swift</c>) stop for stop.
/// </summary>
public static class OverlayDismissScale
{
    private static readonly int[] Stops = { 30, 60, 120, 300, 600, 900, 1800 };

    /// <summary>The finite stops, shortest first, in seconds. A slider position is an index into this.</summary>
    public static IReadOnlyList<int> FiniteStops => Stops;

    /// <summary>Persisted value that means "never auto-dismiss".</summary>
    public const int NeverSeconds = 0;

    /// <summary>Lowest slider position — the 30-second stop.</summary>
    public const int MinPosition = 0;

    /// <summary>Slider position of the trailing "Never" stop, one past the last finite stop.</summary>
    public static int NeverPosition => Stops.Length;

    /// <summary>Slider position for a persisted seconds value. 0 or negative maps to the "Never" stop; any
    /// other value snaps to the nearest stop and returns that stop's index.</summary>
    public static int SecondsToPosition(int seconds) =>
        seconds <= 0 ? NeverPosition : Array.IndexOf(Stops, Snap(seconds));

    /// <summary>Persisted seconds for a slider position. At/after the "Never" stop maps to 0; otherwise the
    /// position is rounded to the nearest stop index and clamped into the table.</summary>
    public static int PositionToSeconds(double position)
    {
        var index = (int)Math.Round(position, MidpointRounding.AwayFromZero);
        return index >= NeverPosition ? NeverSeconds : Stops[Math.Max(index, MinPosition)];
    }

    /// <summary>Rounds a persisted value to the nearest stop, so a legacy value (for example the 6-second
    /// default shipped before the 30s…30m scale) still resolves to a value the slider can show and the
    /// overlay can honour. Ties break toward the shorter stop.</summary>
    public static int Snap(int seconds)
    {
        if (seconds <= 0) return NeverSeconds;
        var best = Stops[0];
        foreach (var stop in Stops)
        {
            if (Math.Abs(stop - seconds) < Math.Abs(best - seconds)) best = stop;
        }
        return best;
    }

    /// <summary>Label shown next to the slider. The "Never" stop renders as ∞ (reads as "forever"
    /// at a glance and stays narrow next to the numeric stops); otherwise e.g. "30s" or "5m".</summary>
    public const string NeverLabel = "∞";

    public static string Label(int seconds) =>
        seconds <= 0 ? NeverLabel : seconds < 60 ? $"{seconds}s" : $"{seconds / 60}m";
}
