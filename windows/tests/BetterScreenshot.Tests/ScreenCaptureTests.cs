using BetterScreenshot.Core;
using BetterScreenshot.Platform;
using Xunit;

namespace BetterScreenshot.Tests;

public class ScreenCaptureTests
{
    [Fact]
    [Trait("category", "hardware")]
    public void CapturesRegionWithExactPixelSize()
    {
        var primary = Screens.Primary();
        var region = new PxRect(primary.Bounds.X, primary.Bounds.Y, 50, 40);
        var bmp = ScreenCapture.CaptureRegion(region);

        Assert.NotNull(bmp);
        Assert.Equal(50, bmp.PixelWidth);
        Assert.Equal(40, bmp.PixelHeight);
        Assert.True(bmp.IsFrozen);
    }
}
