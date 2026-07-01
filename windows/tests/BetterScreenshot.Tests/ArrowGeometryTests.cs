using BetterScreenshot.Core;
using BetterScreenshot.Editor;
using Xunit;

namespace BetterScreenshot.Tests;

public class ArrowGeometryTests
{
    [Fact]
    public void HorizontalArrowheadWings()
    {
        var (left, right) = ArrowGeometry.HeadWings(new PxPoint(0, 0), new PxPoint(100, 0), length: 20, halfAngleDegrees: 28);
        // Symmetric across the shaft (x-axis), same X, and behind the tip.
        Assert.Equal(left.X, right.X, 6);
        Assert.Equal(left.Y, -right.Y, 6);
        Assert.True(left.X < 100);
        // Each wing is `length` from the tip.
        Assert.Equal(20, Dist(new PxPoint(100, 0), left), 6);
        Assert.Equal(20, Dist(new PxPoint(100, 0), right), 6);
    }

    [Fact]
    public void ShaftEndStopsAtArrowheadBase()
    {
        var s = ArrowGeometry.ShaftEnd(new PxPoint(0, 0), new PxPoint(100, 0), headLength: 20, halfAngleDegrees: 28);
        double expected = 100 - 20 * Math.Cos(28 * Math.PI / 180.0); // 82.34
        Assert.Equal(expected, s.X, 6);
        Assert.Equal(0, s.Y, 6);
    }

    [Fact]
    public void ShaftEndClampsToStartForShortArrow()
    {
        var start = new PxPoint(0, 0);
        var s = ArrowGeometry.ShaftEnd(start, new PxPoint(10, 0), headLength: 20, halfAngleDegrees: 28);
        Assert.Equal(start, s);
    }

    private static double Dist(PxPoint a, PxPoint b) => Math.Sqrt(Math.Pow(a.X - b.X, 2) + Math.Pow(a.Y - b.Y, 2));
}
