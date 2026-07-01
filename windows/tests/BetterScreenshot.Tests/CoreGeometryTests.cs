using BetterScreenshot.Core;
using Xunit;

namespace BetterScreenshot.Tests;

public class CoreGeometryTests
{
    [Fact]
    public void Intersection_Overlap()
    {
        var r = new PxRect(0, 0, 100, 100).Intersection(new PxRect(90, 90, 50, 50));
        Assert.Equal(new PxRect(90, 90, 10, 10), r);
    }

    [Fact]
    public void Intersection_Disjoint_IsEmpty()
    {
        var r = new PxRect(0, 0, 10, 10).Intersection(new PxRect(50, 50, 10, 10));
        Assert.True(r.IsEmpty);
    }

    [Fact]
    public void Integral_ExpandsToContainingIntegerRect()
    {
        var r = new PxRect(10.2, 20.9, 5.5, 4.1).Integral();
        Assert.Equal(10, r.X);
        Assert.Equal(20, r.Y);
        Assert.Equal(16, r.Right);  // ceil(15.7)
        Assert.Equal(25, r.Bottom); // ceil(25.0)
    }

    [Fact]
    public void Contains_IsHalfOpen()
    {
        var r = new PxRect(0, 0, 10, 10);
        Assert.True(r.Contains(new PxPoint(0, 0)));
        Assert.True(r.Contains(new PxPoint(9.9, 9.9)));
        Assert.False(r.Contains(new PxPoint(10, 10)));
    }
}
