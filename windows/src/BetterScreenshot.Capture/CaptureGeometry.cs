using BetterScreenshot.Core;

namespace BetterScreenshot.Capture;

/// <summary>
/// Converts a selection rectangle (top-left, logical coords within a display) into a top-left pixel rect
/// relative to that display's captured image. Windows is top-left origin everywhere, so — unlike the macOS
/// version — there is no Y-flip.
/// </summary>
public static class CaptureGeometry
{
    public static PxRect PixelRect(PxRect selection, PxRect display, double scale) =>
        new((selection.X - display.X) * scale,
            (selection.Y - display.Y) * scale,
            selection.Width * scale,
            selection.Height * scale);
}
