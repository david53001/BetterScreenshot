using System.Windows.Media.Imaging;
using BetterScreenshot.Core;
using PixelFormats = System.Windows.Media.PixelFormats;

namespace BetterScreenshot.App.Editor;

/// <summary>Conversions between the headless <see cref="ArgbImage"/> (RGBA) and WPF <see cref="BitmapSource"/> (BGRA).</summary>
public static class ImageConvert
{
    public static BitmapSource ToBitmapSource(ArgbImage image)
    {
        int stride = image.Width * 4;
        var bgra = new byte[image.Height * stride];
        for (int i = 0; i < image.Width * image.Height; i++)
        {
            int s = i * 4;
            bgra[s] = image.Pixels[s + 2];     // B
            bgra[s + 1] = image.Pixels[s + 1]; // G
            bgra[s + 2] = image.Pixels[s];     // R
            bgra[s + 3] = image.Pixels[s + 3]; // A
        }
        var bmp = BitmapSource.Create(image.Width, image.Height, 96, 96, PixelFormats.Bgra32, null, bgra, stride);
        bmp.Freeze();
        return bmp;
    }

    public static ArgbImage ToArgbImage(BitmapSource source)
    {
        var converted = source.Format == PixelFormats.Bgra32
            ? source
            : new FormatConvertedBitmap(source, PixelFormats.Bgra32, null, 0);
        int w = converted.PixelWidth, h = converted.PixelHeight, stride = w * 4;
        var bgra = new byte[h * stride];
        converted.CopyPixels(bgra, stride, 0);

        var rgba = new byte[bgra.Length];
        for (int i = 0; i < w * h; i++)
        {
            int s = i * 4;
            rgba[s] = bgra[s + 2];     // R
            rgba[s + 1] = bgra[s + 1]; // G
            rgba[s + 2] = bgra[s];     // B
            rgba[s + 3] = bgra[s + 3]; // A
        }
        return new ArgbImage(w, h, rgba);
    }
}
