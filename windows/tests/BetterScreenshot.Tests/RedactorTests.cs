using BetterScreenshot.Core;
using BetterScreenshot.Editor;
using Xunit;

namespace BetterScreenshot.Tests;

public class RedactorTests
{
    /// <summary>A high-contrast image of 1px-wide alternating black/white vertical stripes.</summary>
    private static ArgbImage Stripes(int w, int h)
    {
        var img = new ArgbImage(w, h);
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                byte v = (byte)(x % 2 == 0 ? 0 : 255);
                img.Set(x, y, v, v, v, 255);
            }
        return img;
    }

    /// <summary>Counts adjacent horizontal pixel pairs whose red channel differs by more than the threshold.</summary>
    private static int HardEdges(ArgbImage img, int threshold = 128)
    {
        int count = 0;
        for (int y = 0; y < img.Height; y++)
            for (int x = 1; x < img.Width; x++)
                if (Math.Abs(img.Get(x, y).R - img.Get(x - 1, y).R) > threshold) count++;
        return count;
    }

    [Fact]
    public void PixelatePatchHasRegionSize()
    {
        var patch = Redactor.Pixelate(new ArgbImage(100, 100), new PxRect(10, 10, 40, 30));
        Assert.NotNull(patch);
        Assert.Equal(40, patch!.Width);
        Assert.Equal(30, patch.Height);
    }

    [Fact]
    public void BlurPatchHasRegionSize()
    {
        var patch = Redactor.Blur(new ArgbImage(100, 100), new PxRect(10, 10, 40, 30));
        Assert.NotNull(patch);
        Assert.Equal(40, patch!.Width);
        Assert.Equal(30, patch.Height);
    }

    [Fact]
    public void TinyRegionReturnsNull()
    {
        Assert.Null(Redactor.Pixelate(new ArgbImage(100, 100), new PxRect(0, 0, 1, 1)));
        Assert.Null(Redactor.Blur(new ArgbImage(100, 100), new PxRect(0, 0, 1, 1)));
    }

    [Fact]
    public void PixelateDestroysDetail()
    {
        var src = Stripes(48, 16);
        int before = HardEdges(src);
        var patch = Redactor.Pixelate(src, new PxRect(0, 0, 48, 16), blockSize: 12)!;
        int after = HardEdges(patch);
        Assert.True(before > 100);
        Assert.True(after < before / 4, $"expected far fewer hard edges after pixelate: before={before}, after={after}");
    }

    [Fact]
    public void BlurDestroysDetail()
    {
        var src = Stripes(48, 16);
        int before = HardEdges(src);
        var patch = Redactor.Blur(src, new PxRect(0, 0, 48, 16), radius: 12)!;
        int after = HardEdges(patch);
        Assert.True(after < before / 4, $"expected far fewer hard edges after blur: before={before}, after={after}");
    }
}
