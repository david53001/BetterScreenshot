using BetterScreenshot.Core;

namespace BetterScreenshot.Capture;

/// <summary>
/// Computes the top-left origin of an overlay window pinned to a screen corner, and stacked positions for
/// the quick-access stack. Top-left origin (Windows): bottom corners stack upward, top corners stack downward.
/// </summary>
public static class OverlayPositioner
{
    public static PxPoint Origin(Corner corner, PxSize overlay, PxRect screen, double margin)
    {
        double left = screen.X + margin;
        double right = screen.Right - overlay.Width - margin;
        double top = screen.Y + margin;
        double bottom = screen.Bottom - overlay.Height - margin;
        return corner switch
        {
            Corner.TopLeft => new PxPoint(left, top),
            Corner.TopRight => new PxPoint(right, top),
            Corner.BottomLeft => new PxPoint(left, bottom),
            Corner.BottomRight => new PxPoint(right, bottom),
            _ => new PxPoint(left, top),
        };
    }

    public static PxPoint StackedOrigin(Corner corner, PxSize overlay, PxRect screen, double margin, int index, double spacing = 12)
    {
        var baseOrigin = Origin(corner, overlay, screen, margin);
        double offset = index * (overlay.Height + spacing);
        bool isBottom = corner is Corner.BottomLeft or Corner.BottomRight;
        double y = isBottom ? baseOrigin.Y - offset : baseOrigin.Y + offset;
        return new PxPoint(baseOrigin.X, y);
    }
}
