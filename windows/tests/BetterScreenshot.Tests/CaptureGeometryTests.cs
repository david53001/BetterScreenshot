using BetterScreenshot.Capture;
using BetterScreenshot.Core;
using Xunit;

namespace BetterScreenshot.Tests;

public class CaptureGeometryTests
{
    [Fact]
    public void ConvertsSelectionToTopLeftPixelRect()
    {
        var px = CaptureGeometry.PixelRect(new PxRect(100, 100, 200, 150), new PxRect(0, 0, 1440, 900), 2);
        Assert.Equal(new PxRect(200, 200, 400, 300), px);
    }

    [Fact]
    public void HandlesNonZeroDisplayOrigin()
    {
        var px = CaptureGeometry.PixelRect(new PxRect(1540, 80, 100, 100), new PxRect(1440, 0, 1920, 1080), 2);
        Assert.Equal(new PxRect(200, 160, 200, 200), px);
    }
}
