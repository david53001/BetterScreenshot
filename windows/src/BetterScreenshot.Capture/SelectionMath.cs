using BetterScreenshot.Core;

namespace BetterScreenshot.Capture;

/// <summary>Pure math for the area-selection overlay: normalize two drag points and map window DIPs to physical pixels.</summary>
public static class SelectionMath
{
    /// <summary>Smallest positive rect spanning two points.</summary>
    public static PxRect Normalize(PxPoint a, PxPoint b) =>
        PxRect.FromLtrb(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y), Math.Max(a.X, b.X), Math.Max(a.Y, b.Y));

    /// <summary>
    /// Clamps a rect to the box [0,width] × [0,height] — the "physical wall" for a drag that runs past the edge
    /// (mouse capture keeps delivering points outside the window). Keeps the selection inside the screen/image so
    /// a capture can never spill off it. Returns a zero-size rect if the input is entirely outside the box.
    /// </summary>
    public static PxRect ClampToBounds(PxRect rect, double width, double height)
    {
        double left = Math.Clamp(rect.X, 0, width);
        double top = Math.Clamp(rect.Y, 0, height);
        double right = Math.Clamp(rect.Right, 0, width);
        double bottom = Math.Clamp(rect.Bottom, 0, height);
        return PxRect.FromLtrb(left, top, right, bottom);
    }

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
