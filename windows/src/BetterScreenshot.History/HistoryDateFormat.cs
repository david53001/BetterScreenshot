namespace BetterScreenshot.History;

/// <summary>
/// Abbreviated relative-time formatting for history cells (mirrors the macOS app's
/// <c>RelativeDateTimeFormatter</c> with <c>.abbreviated</c> units: "now", "2m ago", "2h ago", "3d ago", …).
/// Pure and deterministic — the caller passes the reference "now" so it is unit-testable.
/// </summary>
public static class HistoryDateFormat
{
    public static string Relative(DateTime now, DateTime date)
    {
        var span = now - date;
        if (span < TimeSpan.Zero) span = TimeSpan.Zero; // clock skew / future → treat as now

        double seconds = span.TotalSeconds;
        if (seconds < 60) return "now";
        if (span.TotalMinutes < 60) return $"{(int)span.TotalMinutes}m ago";
        if (span.TotalHours < 24) return $"{(int)span.TotalHours}h ago";
        if (span.TotalDays < 7) return $"{(int)span.TotalDays}d ago";
        if (span.TotalDays < 30) return $"{(int)(span.TotalDays / 7)}w ago";
        if (span.TotalDays < 365) return $"{(int)(span.TotalDays / 30)}mo ago";
        return $"{(int)(span.TotalDays / 365)}y ago";
    }
}
