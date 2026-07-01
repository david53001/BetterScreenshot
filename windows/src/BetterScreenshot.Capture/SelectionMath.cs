using BetterScreenshot.Core;

namespace BetterScreenshot.Capture;

/// <summary>Pure math for the area-selection overlay: normalize two drag points and map window DIPs to physical pixels.</summary>
public static class SelectionMath
{
    /// <summary>Smallest positive rect spanning two points.</summary>
    public static PxRect Normalize(PxPoint a, PxPoint b) =>
        PxRect.FromLtrb(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y), Math.Max(a.X, b.X), Math.Max(a.Y, b.Y));

    /// <summary>
    /// Convert a selection rect in window DIP coordinates to physical screen pixels, given the window's monitor
    /// physical bounds (top-left origin) and DPI scale (physical = logical × scale).
    /// </summary>
    public static PxRect DipToPhysical(PxRect dipRect, PxRect monitorPhysical, double dpiScale) =>
        new(monitorPhysical.X + dipRect.X * dpiScale,
            monitorPhysical.Y + dipRect.Y * dpiScale,
            dipRect.Width * dpiScale,
            dipRect.Height * dpiScale);
}
