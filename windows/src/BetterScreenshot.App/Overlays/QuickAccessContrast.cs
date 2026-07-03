using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Brush = System.Windows.Media.Brush;
using Color = System.Windows.Media.Color;
using Point = System.Windows.Point;

namespace BetterScreenshot.App.Overlays;

/// <summary>
/// Pure luminance helpers for the Quick Access card's auto-contrast (kept WPF-window-free so they're unit
/// testable). The card overlays its action buttons directly on the captured image, so the glyphs / hover
/// pills / bottom scrim must flip between light and dark to stay legible against whatever the image shows.
/// </summary>
public static class QuickAccessContrast
{
    /// <summary>Average relative luminance above which the strip behind the toolbar counts as "light"
    /// (→ dark controls). Below it, controls go light.</summary>
    public const double LightThreshold = 0.58;

    /// <summary>Average relative luminance (0..1) of a 32bpp BGRA pixel buffer; alpha is ignored.</summary>
    public static double AverageLuminance(byte[] bgra, int stride, int width, int height)
    {
        if (bgra.Length == 0 || width <= 0 || height <= 0) return 0.0;

        double sum = 0;
        long n = 0;
        for (int y = 0; y < height; y++)
        {
            int row = y * stride;
            for (int x = 0; x < width; x++)
            {
                int i = row + x * 4;
                double b = bgra[i] / 255.0, g = bgra[i + 1] / 255.0, r = bgra[i + 2] / 255.0;
                sum += 0.2126 * r + 0.7152 * g + 0.0722 * b; // Rec. 709 relative luminance
                n++;
            }
        }
        return n > 0 ? sum / n : 0.0;
    }

    public static bool IsLightBackground(double luminance) => luminance > LightThreshold;
}

/// <summary>
/// A light-or-dark control palette derived from the average luminance of the image's bottom strip (where the
/// toolbar sits): a bright strip → near-black glyphs + a light scrim; a dark strip → near-white glyphs + a
/// dark scrim. Every part (glyph, hover pill, pressed pill, scrim) comes from that single decision so the
/// overlaid toolbar reads as one coherent, auto-contrasting unit against any wallpaper/screenshot behind it.
/// </summary>
internal sealed class ContrastPalette
{
    public Brush Glyph { get; }
    public Brush Hover { get; }
    public Brush Pressed { get; }
    public Brush Scrim { get; } // vertical gradient: transparent (top) → tone (bottom)
    public bool IsLightBackground { get; }

    private ContrastPalette(bool light, Brush glyph, Brush hover, Brush pressed, Brush scrim)
    {
        IsLightBackground = light;
        Glyph = glyph;
        Hover = hover;
        Pressed = pressed;
        Scrim = scrim;
    }

    public static ContrastPalette ForImageBottom(BitmapSource image)
    {
        bool light = QuickAccessContrast.IsLightBackground(SampleBottomLuminance(image));

        // Light image → dark controls over a faint white scrim. Dark image → light controls over a faint
        // black scrim. The scrim shares the image's tone so the (opposite-tone) glyph always pops, even over
        // busy/mixed content near the bottom edge.
        return light
            ? new ContrastPalette(true,
                Frozen(Color.FromRgb(0x18, 0x18, 0x1A)),
                Frozen(Color.FromArgb(0x24, 0x00, 0x00, 0x00)),
                Frozen(Color.FromArgb(0x3D, 0x00, 0x00, 0x00)),
                BottomScrim(0xFF, 0xFF, 0xFF, 0x8C))
            : new ContrastPalette(false,
                Frozen(Color.FromRgb(0xF4, 0xF4, 0xF6)),
                Frozen(Color.FromArgb(0x2B, 0xFF, 0xFF, 0xFF)),
                Frozen(Color.FromArgb(0x45, 0xFF, 0xFF, 0xFF)),
                BottomScrim(0x00, 0x00, 0x00, 0x8C));
    }

    private static SolidColorBrush Frozen(Color c)
    {
        var b = new SolidColorBrush(c);
        b.Freeze();
        return b;
    }

    private static LinearGradientBrush BottomScrim(byte r, byte g, byte b, byte bottomAlpha)
    {
        var brush = new LinearGradientBrush { StartPoint = new Point(0, 0), EndPoint = new Point(0, 1) };
        brush.GradientStops.Add(new GradientStop(Color.FromArgb(0x00, r, g, b), 0.0));
        brush.GradientStops.Add(new GradientStop(Color.FromArgb((byte)(bottomAlpha / 3), r, g, b), 0.5));
        brush.GradientStops.Add(new GradientStop(Color.FromArgb(bottomAlpha, r, g, b), 1.0));
        brush.Freeze();
        return brush;
    }

    /// <summary>Average luminance of the image's bottom ~30% strip, sampled cheaply (crop → downscale → BGRA).</summary>
    private static double SampleBottomLuminance(BitmapSource image)
    {
        try
        {
            int w = image.PixelWidth, h = image.PixelHeight;
            if (w <= 0 || h <= 0) return 0.0;

            int stripH = Math.Max(1, (int)(h * 0.30));
            var strip = new CroppedBitmap(image, new Int32Rect(0, h - stripH, w, stripH));

            double scale = Math.Min(1.0, 48.0 / Math.Max(strip.PixelWidth, strip.PixelHeight));
            BitmapSource small = scale < 1.0 ? new TransformedBitmap(strip, new ScaleTransform(scale, scale)) : strip;
            var bgra = new FormatConvertedBitmap(small, PixelFormats.Bgra32, null, 0);

            int sw = bgra.PixelWidth, sh = bgra.PixelHeight, stride = sw * 4;
            var px = new byte[stride * sh];
            bgra.CopyPixels(px, stride, 0);
            return QuickAccessContrast.AverageLuminance(px, stride, sw, sh);
        }
        catch
        {
            return 0.0; // fall back to the dark-background palette (light glyphs)
        }
    }
}
