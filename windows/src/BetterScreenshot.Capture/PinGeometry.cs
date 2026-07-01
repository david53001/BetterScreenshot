using BetterScreenshot.Core;

namespace BetterScreenshot.Capture;

/// <summary>
/// Pure geometry for pin-to-screen panels: the initial floating frame for a captured image (sized in logical
/// units, clamped to ≤80% of the visible area, centered on the source region and kept on-screen), and
/// aspect-locked zoom about the frame center clamped to 0.25×–3×.
/// </summary>
public static class PinGeometry
{
    public static PxRect InitialFrame(PxSize imagePixelSize, double dpiScale, PxRect visibleFrame, PxRect? sourceRect = null, double maxFraction = 0.8)
    {
        double w = imagePixelSize.Width / dpiScale;
        double h = imagePixelSize.Height / dpiScale;

        // Shrink (never enlarge) to fit within maxFraction of the visible area, preserving aspect.
        double maxW = visibleFrame.Width * maxFraction;
        double maxH = visibleFrame.Height * maxFraction;
        double scale = Math.Min(1.0, Math.Min(maxW / w, maxH / h));
        w *= scale;
        h *= scale;

        PxPoint center = sourceRect?.Center ?? visibleFrame.Center;
        double x = center.X - w / 2;
        double y = center.Y - h / 2;

        // Keep fully inside the visible frame.
        x = Math.Clamp(x, visibleFrame.X, Math.Max(visibleFrame.X, visibleFrame.Right - w));
        y = Math.Clamp(y, visibleFrame.Y, Math.Max(visibleFrame.Y, visibleFrame.Bottom - h));
        return new PxRect(x, y, w, h);
    }

    public static PxRect ZoomedFrame(PxRect current, PxSize naturalSize, double factor, double minScale = 0.25, double maxScale = 3.0)
    {
        double currentScale = current.Width / naturalSize.Width;
        double newScale = Math.Clamp(currentScale * factor, minScale, maxScale);
        double newW = naturalSize.Width * newScale;
        double newH = naturalSize.Height * newScale;
        var c = current.Center;
        return new PxRect(c.X - newW / 2, c.Y - newH / 2, newW, newH);
    }
}
