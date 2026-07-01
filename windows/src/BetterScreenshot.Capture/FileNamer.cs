using System.Globalization;

namespace BetterScreenshot.Capture;

/// <summary>
/// Deterministic, locale-independent capture filenames, e.g. "Screenshot 2026-06-02 at 14.32.10.png".
/// Uses dots (not colons) for the time so the name is valid on Windows and matches the macOS app.
/// </summary>
public static class FileNamer
{
    public static string Name(DateTime date, string ext, string prefix = "Screenshot")
    {
        string stamp = date.ToString("yyyy-MM-dd 'at' HH.mm.ss", CultureInfo.InvariantCulture);
        return $"{prefix} {stamp}.{ext}";
    }
}
