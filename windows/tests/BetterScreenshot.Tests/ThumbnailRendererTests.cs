using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.Platform;
using Xunit;

namespace BetterScreenshot.Tests;

public class ThumbnailRendererTests
{
    private static byte[] Png(int w, int h)
    {
        int stride = w * 4;
        var px = new byte[h * stride];
        for (int i = 0; i < px.Length; i += 4) { px[i] = 0; px[i + 1] = 0; px[i + 2] = 200; px[i + 3] = 255; }
        return ImageIo.EncodePng(BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, px, stride));
    }

    [Fact]
    public void CapsLongestSideAt400()
    {
        var thumb = ThumbnailRenderer.JpegThumbnail(Png(1600, 1000));
        Assert.NotNull(thumb);
        var size = ThumbnailRenderer.PixelSize(thumb!);
        Assert.NotNull(size);
        Assert.Equal(400, size!.Value.Width);
        Assert.Equal(250, size.Value.Height);
    }

    [Fact]
    public void SmallImagesAreNotUpscaled()
    {
        var thumb = ThumbnailRenderer.JpegThumbnail(Png(200, 100));
        var size = ThumbnailRenderer.PixelSize(thumb!);
        Assert.Equal(200, size!.Value.Width);
        Assert.Equal(100, size.Value.Height);
    }

    [Fact]
    public void OutputIsJpeg()
    {
        var thumb = ThumbnailRenderer.JpegThumbnail(Png(300, 300))!;
        Assert.Equal(0xFF, thumb[0]);
        Assert.Equal(0xD8, thumb[1]);
    }

    [Fact]
    public void GarbageDataReturnsNull()
    {
        Assert.Null(ThumbnailRenderer.JpegThumbnail(new byte[] { 1, 2, 3, 4 }));
        Assert.Null(ThumbnailRenderer.PixelSize(new byte[] { 1, 2, 3, 4 }));
    }
}
