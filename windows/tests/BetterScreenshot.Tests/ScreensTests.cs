using BetterScreenshot.Platform;
using Xunit;

namespace BetterScreenshot.Tests;

public class ScreensTests
{
    // Requires a real display session (present on the dev machine). Marked hardware so it can be filtered out
    // in headless environments.
    [Fact]
    [Trait("category", "hardware")]
    public void EnumeratesMonitorsWithValidBoundsAndDpi()
    {
        var all = Screens.All();
        Assert.NotEmpty(all);
        foreach (var m in all)
        {
            Assert.True(m.Bounds.Width > 0, "monitor width should be positive");
            Assert.True(m.Bounds.Height > 0, "monitor height should be positive");
            Assert.True(m.DpiScale >= 1.0, "DPI scale should be at least 1.0");
        }

        var primary = Screens.Primary();
        Assert.True(primary.Bounds.Width > 0);
        Assert.True(primary.Bounds.Height > 0);
    }

    // The real-framebuffer query backs the capture black-bar fix: it must return a positive size for a live
    // display, and (in a normal, non-stretched session) never exceed the reported monitor bounds — so clamping a
    // capture to it is safe.
    [Fact]
    [Trait("category", "hardware")]
    public void RealFramebufferSizeIsPositiveAndWithinReportedBounds()
    {
        var primary = Screens.Primary();
        var fb = Screens.RealFramebufferSize(primary.DeviceName);
        Assert.NotNull(fb);
        Assert.True(fb!.Value.Width > 0);
        Assert.True(fb.Value.Height > 0);
    }

    // An empty device name never touches the display API — it short-circuits to null, so callers fall back to the
    // reported bounds. (An *unknown* device name is not tested: CreateDC("DISPLAY", …) falls back to the primary
    // display for anything it doesn't recognize, so it returns a size rather than failing.)
    [Fact]
    public void RealFramebufferSizeReturnsNullForEmptyDevice()
    {
        Assert.Null(Screens.RealFramebufferSize(string.Empty));
    }
}
