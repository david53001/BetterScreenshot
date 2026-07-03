using BetterScreenshot.Core;

namespace BetterScreenshot.Recording;

/// <summary>Pure frame-time and downscale math for MP4→GIF export.</summary>
public static class GIFTiming
{
    /// <summary>Frame sample times [0, 1/fps, 2/fps, …) covering <paramref name="duration"/> seconds.</summary>
    public static IReadOnlyList<double> FrameTimes(double duration, int fps)
    {
        var times = new List<double>();
        if (fps <= 0 || duration <= 0) return times;
        double step = 1.0 / fps;
        int count = (int)Math.Floor(duration * fps + 1e-9);
        for (int i = 0; i < count; i++) times.Add(i * step);
        return times;
    }

    /// <summary>Aspect-preserving downscale so width ≤ <paramref name="maxWidth"/>; never upscales.</summary>
    public static PxSize OutputSize(PxSize source, double maxWidth)
    {
        if (source.Width <= maxWidth) return source;
        double scale = maxWidth / source.Width;
        return new PxSize(maxWidth, Math.Round(source.Height * scale));
    }
}
