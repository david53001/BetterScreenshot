using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.Platform;
using Xunit;

namespace BetterScreenshot.Tests;

public class ImageIoTests
{
    private static readonly byte[] PngMagic = { 0x89, 0x50, 0x4E, 0x47 };

    private static BitmapSource TinyRed()
    {
        const int w = 4, h = 4, stride = w * 4;
        var px = new byte[h * stride];
        for (int i = 0; i < px.Length; i += 4) { px[i] = 0; px[i + 1] = 0; px[i + 2] = 255; px[i + 3] = 255; } // BGRA red
        return BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, px, stride);
    }

    [Fact]
    public void EncodePngHasSignature()
    {
        var bytes = ImageIo.EncodePng(TinyRed());
        Assert.True(bytes.Length > 8);
        Assert.Equal(PngMagic, bytes[..4]);
    }

    [Fact]
    public void EncodeJpgHasSignature()
    {
        var bytes = ImageIo.EncodeJpg(TinyRed(), 80);
        Assert.Equal(0xFF, bytes[0]);
        Assert.Equal(0xD8, bytes[1]);
    }

    [Fact]
    public void WriteTempPngCreatesValidFile()
    {
        var path = ImageIo.WriteTempPng(TinyRed(), "shot.png");
        var dir = Path.GetDirectoryName(path);
        try
        {
            Assert.True(File.Exists(path));
            Assert.EndsWith(".png", path);
            Assert.Equal(PngMagic, File.ReadAllBytes(path)[..4]);
        }
        finally
        {
            if (dir != null && Directory.Exists(dir)) Directory.Delete(dir, true);
        }
    }

    [Fact]
    public void SaveJpgWritesFile()
    {
        var dir = Path.Combine(Path.GetTempPath(), "bs-test-" + Guid.NewGuid().ToString("N"));
        var path = Path.Combine(dir, "x.jpg");
        try
        {
            ImageIo.SaveJpg(TinyRed(), path, 70);
            Assert.True(File.Exists(path));
            var head = File.ReadAllBytes(path);
            Assert.Equal(0xFF, head[0]);
            Assert.Equal(0xD8, head[1]);
        }
        finally
        {
            if (Directory.Exists(dir)) Directory.Delete(dir, true);
        }
    }
}
