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

    // Regression for the "black bar on the side" capture bug: CaptureDisplay is clamped to the monitor's real
    // framebuffer, so the returned bitmap never exceeds the reported bounds (and equals the real framebuffer when
    // that is known). If a game/stretched resolution left the scanout narrower than GetMonitorInfo reports, this is
    // what stops BitBlt from padding a black bar onto the right/bottom.
    [Fact]
    [Trait("category", "hardware")]
    public void CaptureDisplayIsClampedToRealFramebuffer()
    {
        var primary = Screens.Primary();
        var bmp = ScreenCapture.CaptureDisplay(primary);

        Assert.True(bmp.PixelWidth <= (int)System.Math.Round(primary.Bounds.Width));
        Assert.True(bmp.PixelHeight <= (int)System.Math.Round(primary.Bounds.Height));

        if (Screens.RealFramebufferSize(primary.DeviceName) is { } fb)
        {
            Assert.Equal((int)System.Math.Round(System.Math.Min(primary.Bounds.Width, fb.Width)), bmp.PixelWidth);
            Assert.Equal((int)System.Math.Round(System.Math.Min(primary.Bounds.Height, fb.Height)), bmp.PixelHeight);
        }
    }
}
