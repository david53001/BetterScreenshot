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
}
