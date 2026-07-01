using BetterScreenshot.Capture;
using BetterScreenshot.Core;
using Xunit;

namespace BetterScreenshot.Tests;

public class SelectionMathTests
{
    [Fact]
    public void NormalizeHandlesAnyDragDirection()
    {
        Assert.Equal(new PxRect(10, 20, 40, 30), SelectionMath.Normalize(new PxPoint(50, 50), new PxPoint(10, 20)));
    }

    [Fact]
    public void DipToPhysicalOnPrimaryAt100Percent()
    {
        var phys = SelectionMath.DipToPhysical(new PxRect(10, 20, 100, 50), new PxRect(0, 0, 1920, 1080), 1.0);
        Assert.Equal(new PxRect(10, 20, 100, 50), phys);
    }

    [Fact]
    public void DipToPhysicalOnScaledSecondaryMonitor()
    {
        // Secondary monitor at physical (1920,0), 150% scale.
        var phys = SelectionMath.DipToPhysical(new PxRect(10, 20, 100, 50), new PxRect(1920, 0, 2560, 1440), 1.5);
        Assert.Equal(new PxRect(1920 + 15, 30, 150, 75), phys);
    }
}
