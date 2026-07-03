using BetterScreenshot.Capture;
using BetterScreenshot.Core;
using Xunit;

namespace BetterScreenshot.Tests;

public class OverlayPositionerTests
{
    private static readonly PxSize Overlay = new(200, 140);
    private static readonly PxRect Primary = new(0, 0, 1440, 900);

    [Fact]
    public void BottomRight()
    {
        Assert.Equal(new PxPoint(1224, 744), OverlayPositioner.Origin(Corner.BottomRight, Overlay, Primary, 16));
    }

    [Fact]
    public void TopLeft()
    {
        Assert.Equal(new PxPoint(16, 16), OverlayPositioner.Origin(Corner.TopLeft, Overlay, Primary, 16));
    }

    [Fact]
    public void TopRightWithDisplayOffset()
    {
        var second = new PxRect(1440, 0, 1920, 1080);
        Assert.Equal(new PxPoint(3140, 20), OverlayPositioner.Origin(Corner.TopRight, Overlay, second, 20));
    }

    [Fact]
    public void StackIndexZeroMatchesBase()
    {
        var b = OverlayPositioner.Origin(Corner.BottomRight, Overlay, Primary, 16);
        var s = OverlayPositioner.StackedOrigin(Corner.BottomRight, Overlay, Primary, 16, 0);
        Assert.Equal(b, s);
    }

    [Fact]
    public void BottomCornersStackUpward()
    {
        var s0 = OverlayPositioner.StackedOrigin(Corner.BottomRight, Overlay, Primary, 16, 0);
        var s1 = OverlayPositioner.StackedOrigin(Corner.BottomRight, Overlay, Primary, 16, 1);
        Assert.Equal(s0.Y - (140 + 12), s1.Y);
        Assert.Equal(s0.X, s1.X);
    }

    [Fact]
    public void TopCornersStackDownward()
    {
        var s0 = OverlayPositioner.StackedOrigin(Corner.TopLeft, Overlay, Primary, 16, 0);
        var s1 = OverlayPositioner.StackedOrigin(Corner.TopLeft, Overlay, Primary, 16, 1);
        Assert.Equal(s0.Y + (140 + 12), s1.Y);
    }
}
