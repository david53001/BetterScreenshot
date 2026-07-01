using BetterScreenshot.Core;

namespace BetterScreenshot.Capture;

/// <summary>Pure crop-rect math: integralize, clamp to image bounds, reject sub-pixel results.</summary>
public static class CropMath
{
    /// <summary>
    /// Integralizes <paramref name="target"/> and clamps it to the image bounds. Returns null if the
    /// resulting rectangle is smaller than 1×1 (nothing meaningful to crop).
    /// </summary>
    public static PxRect? ClampCrop(PxRect target, PxSize imageSize)
    {
        var bounds = new PxRect(0, 0, imageSize.Width, imageSize.Height);
        var clamped = target.Integral().Intersection(bounds);
        if (clamped.Width < 1 || clamped.Height < 1) return null;
        return clamped;
    }
}
