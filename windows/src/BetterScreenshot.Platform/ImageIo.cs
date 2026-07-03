using System.IO;
using System.Windows.Media.Imaging;

namespace BetterScreenshot.Platform;

/// <summary>PNG/JPG encoding and saving for captured images, plus temp-file writing for clipboard/drag payloads.</summary>
public static class ImageIo
{
    public static byte[] EncodePng(BitmapSource image)
    {
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(image));
        using var ms = new MemoryStream();
        encoder.Save(ms);
        return ms.ToArray();
    }

    public static byte[] EncodeJpg(BitmapSource image, int quality = 90)
    {
        var encoder = new JpegBitmapEncoder { QualityLevel = Math.Clamp(quality, 1, 100) };
        encoder.Frames.Add(BitmapFrame.Create(image));
        using var ms = new MemoryStream();
        encoder.Save(ms);
        return ms.ToArray();
    }

    public static void SavePng(BitmapSource image, string path)
    {
        EnsureDirectory(path);
        File.WriteAllBytes(path, EncodePng(image));
    }

    public static void SaveJpg(BitmapSource image, string path, int quality = 90)
    {
        EnsureDirectory(path);
        File.WriteAllBytes(path, EncodeJpg(image, quality));
    }

    /// <summary>Writes a PNG into a unique temp subdirectory and returns the file path (caller/cleanup owns it).</summary>
    public static string WriteTempPng(BitmapSource image, string fileName)
    {
        string dir = Path.Combine(Path.GetTempPath(), "BetterScreenshot-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        string path = Path.Combine(dir, fileName);
        File.WriteAllBytes(path, EncodePng(image));
        return path;
    }

    private static void EnsureDirectory(string path)
    {
        string? dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
    }
}
