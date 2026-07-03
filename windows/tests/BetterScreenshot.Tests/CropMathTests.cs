using BetterScreenshot.Capture;
using BetterScreenshot.Core;
using Xunit;

namespace BetterScreenshot.Tests;

public class CropMathTests
{
    [Fact]
    public void CropsExactRect()
    {
        var r = CropMath.ClampCrop(new PxRect(10, 20, 50, 30), new PxSize(200, 100));
        Assert.NotNull(r);
        Assert.Equal(new PxRect(10, 20, 50, 30), r!.Value);
    }

    [Fact]
    public void ClampsToImageBounds()
    {
        var r = CropMath.ClampCrop(new PxRect(90, 90, 50, 50), new PxSize(100, 100));
        Assert.NotNull(r);
        Assert.Equal(new PxRect(90, 90, 10, 10), r!.Value);
    }

    [Fact]
    public void ReturnsNullForZeroArea()
    {
        Assert.Null(CropMath.ClampCrop(new PxRect(0, 0, 0, 0), new PxSize(100, 100)));
    }
}
