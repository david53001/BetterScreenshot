using BetterScreenshot.Core;

namespace BetterScreenshot.Editor;

/// <summary>
/// Buffer-based redaction: produces a pixelated or blurred patch for a region of a base image. Operates on the
/// headless <see cref="ArgbImage"/> so it is unit-testable; the WPF layer converts BitmapSource↔ArgbImage and
/// blits the returned patch into the annotation's frame. Returns null if the region is smaller than 2×2.
/// </summary>
public static class Redactor
{
    /// <summary>Averages the region into <paramref name="blockSize"/>-square blocks (mosaic).</summary>
    public static ArgbImage? Pixelate(ArgbImage source, PxRect region, int blockSize = 12)
    {
        if (TryRegion(region, source) is not (var x0, var y0, var w, var h)) return null;
        var patch = source.Crop(x0, y0, w, h);

        for (int by = 0; by < h; by += blockSize)
        {
            for (int bx = 0; bx < w; bx += blockSize)
            {
                int bw = Math.Min(blockSize, w - bx);
                int bh = Math.Min(blockSize, h - by);
                long sr = 0, sg = 0, sb = 0, sa = 0;
                int count = bw * bh;
                for (int yy = 0; yy < bh; yy++)
                {
                    for (int xx = 0; xx < bw; xx++)
                    {
                        var (pr, pg, pb, pa) = patch.Get(bx + xx, by + yy);
                        sr += pr; sg += pg; sb += pb; sa += pa;
                    }
                }
                byte ar = (byte)(sr / count), ag = (byte)(sg / count), ab = (byte)(sb / count), aa = (byte)(sa / count);
                for (int yy = 0; yy < bh; yy++)
                    for (int xx = 0; xx < bw; xx++)
                        patch.Set(bx + xx, by + yy, ar, ag, ab, aa);
            }
        }
        return patch;
    }

    /// <summary>Separable box blur (two passes) of radius <paramref name="radius"/> over the region.</summary>
    public static ArgbImage? Blur(ArgbImage source, PxRect region, int radius = 12)
    {
        if (TryRegion(region, source) is not (var x0, var y0, var w, var h)) return null;
        var patch = source.Crop(x0, y0, w, h);
        var tmp = new ArgbImage(w, h);
        BoxPass(patch, tmp, radius, horizontal: true);
        var result = new ArgbImage(w, h);
        BoxPass(tmp, result, radius, horizontal: false);
        return result;
    }

    private static (int X, int Y, int W, int H)? TryRegion(PxRect region, ArgbImage source)
    {
        int x = Math.Clamp((int)Math.Floor(region.X), 0, source.Width);
        int y = Math.Clamp((int)Math.Floor(region.Y), 0, source.Height);
        int w = Math.Min((int)Math.Ceiling(region.Width), source.Width - x);
        int h = Math.Min((int)Math.Ceiling(region.Height), source.Height - y);
        if (w < 2 || h < 2) return null;
        return (x, y, w, h);
    }

    private static void BoxPass(ArgbImage src, ArgbImage dst, int radius, bool horizontal)
    {
        for (int y = 0; y < src.Height; y++)
        {
            for (int x = 0; x < src.Width; x++)
            {
                long sr = 0, sg = 0, sb = 0, sa = 0;
                int count = 0;
                for (int k = -radius; k <= radius; k++)
                {
                    int sx = horizontal ? x + k : x;
                    int sy = horizontal ? y : y + k;
                    if (sx < 0 || sx >= src.Width || sy < 0 || sy >= src.Height) continue;
                    var (pr, pg, pb, pa) = src.Get(sx, sy);
                    sr += pr; sg += pg; sb += pb; sa += pa; count++;
                }
                dst.Set(x, y, (byte)(sr / count), (byte)(sg / count), (byte)(sb / count), (byte)(sa / count));
            }
        }
    }
}
