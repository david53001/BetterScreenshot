namespace BetterScreenshot.Core;

/// <summary>
/// Headless 32-bit image buffer (RGBA, 8 bits/channel, row-major, no stride padding). Lets pure-logic
/// image operations (e.g. the redactor's pixelate/blur) be unit-tested without any WPF/GDI dependency.
/// The WPF layer converts between <see cref="ArgbImage"/> and BitmapSource at the boundary.
/// </summary>
public sealed class ArgbImage
{
    public int Width { get; }
    public int Height { get; }

    /// <summary>Row-major RGBA bytes, length = Width*Height*4.</summary>
    public byte[] Pixels { get; }

    public ArgbImage(int width, int height)
    {
        if (width <= 0 || height <= 0) throw new ArgumentOutOfRangeException(nameof(width), "dimensions must be positive");
        Width = width;
        Height = height;
        Pixels = new byte[width * height * 4];
    }

    public ArgbImage(int width, int height, byte[] pixels)
    {
        if (width <= 0 || height <= 0) throw new ArgumentOutOfRangeException(nameof(width), "dimensions must be positive");
        if (pixels.Length != width * height * 4) throw new ArgumentException("pixel buffer size mismatch", nameof(pixels));
        Width = width;
        Height = height;
        Pixels = pixels;
    }

    private int Index(int x, int y) => (y * Width + x) * 4;

    public (byte R, byte G, byte B, byte A) Get(int x, int y)
    {
        int i = Index(x, y);
        return (Pixels[i], Pixels[i + 1], Pixels[i + 2], Pixels[i + 3]);
    }

    public void Set(int x, int y, byte r, byte g, byte b, byte a)
    {
        int i = Index(x, y);
        Pixels[i] = r; Pixels[i + 1] = g; Pixels[i + 2] = b; Pixels[i + 3] = a;
    }

    /// <summary>Returns a new image containing the given region (caller ensures it is in bounds).</summary>
    public ArgbImage Crop(int x, int y, int w, int h)
    {
        var outImg = new ArgbImage(w, h);
        for (int yy = 0; yy < h; yy++)
        {
            for (int xx = 0; xx < w; xx++)
            {
                var (r, g, b, a) = Get(x + xx, y + yy);
                outImg.Set(xx, yy, r, g, b, a);
            }
        }
        return outImg;
    }
}
