using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.Core;

namespace BetterScreenshot.Platform;

/// <summary>Generates JPEG thumbnails: downscale the longest side to ≤ maxPixelSize (never upscale), encode JPEG.</summary>
public static class ThumbnailRenderer
{
    public static byte[]? JpegThumbnail(byte[] imageData, int maxPixelSize = 400, double quality = 0.8)
    {
        var source = Decode(imageData);
        if (source is null) return null;

        double scale = Math.Min(1.0, (double)maxPixelSize / Math.Max(source.PixelWidth, source.PixelHeight));
        BitmapSource scaled = scale < 1.0 ? new TransformedBitmap(source, new ScaleTransform(scale, scale)) : source;

        var encoder = new JpegBitmapEncoder { QualityLevel = Math.Clamp((int)Math.Round(quality * 100), 1, 100) };
        encoder.Frames.Add(BitmapFrame.Create(scaled));
        using var ms = new MemoryStream();
        encoder.Save(ms);
        return ms.ToArray();
    }

    public static PxSize? PixelSize(byte[] imageData)
    {
        var source = Decode(imageData);
        return source is null ? null : new PxSize(source.PixelWidth, source.PixelHeight);
    }

    private static BitmapSource? Decode(byte[] data)
    {
        try
        {
            using var ms = new MemoryStream(data);
            var decoder = BitmapDecoder.Create(ms, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
            var frame = decoder.Frames[0];
            frame.Freeze();
            return frame;
        }
        catch
        {
            return null;
        }
    }
}
