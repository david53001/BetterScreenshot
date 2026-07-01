using BetterScreenshot.Capture;
using BetterScreenshot.Core;
using Xunit;

namespace BetterScreenshot.Tests;

public class PinGeometryTests
{
    [Fact]
    public void RetinaImageGetsPointSize()
    {
        var f = PinGeometry.InitialFrame(new PxSize(400, 200), dpiScale: 2, new PxRect(0, 0, 2000, 2000));
        Assert.Equal(200, f.Width, 6);
        Assert.Equal(100, f.Height, 6);
    }

    [Fact]
    public void CentersOnVisibleFrameWithoutSource()
    {
        var vf = new PxRect(0, 0, 1000, 800);
        var f = PinGeometry.InitialFrame(new PxSize(200, 100), 1, vf);
        Assert.Equal(vf.Center.X, f.Center.X, 6);
        Assert.Equal(vf.Center.Y, f.Center.Y, 6);
    }

    [Fact]
    public void CentersOnSourceRect()
    {
        var vf = new PxRect(0, 0, 1000, 800);
        var f = PinGeometry.InitialFrame(new PxSize(100, 100), 1, vf, new PxRect(400, 300, 50, 50));
        Assert.Equal(425, f.Center.X, 6);
        Assert.Equal(325, f.Center.Y, 6);
    }

    [Fact]
    public void ClampsTo80PercentOfScreen()
    {
        var f = PinGeometry.InitialFrame(new PxSize(4000, 2000), 1, new PxRect(0, 0, 1000, 800));
        Assert.Equal(800, f.Width, 6);
        Assert.Equal(400, f.Height, 6);
    }

    [Fact]
    public void ClampsHeightLimitedImages()
    {
        var f = PinGeometry.InitialFrame(new PxSize(1000, 2000), 1, new PxRect(0, 0, 1000, 800));
        Assert.Equal(640, f.Height, 6); // 80% of 800
        Assert.Equal(320, f.Width, 6);
    }

    [Fact]
    public void StaysInsideVisibleFrame()
    {
        var vf = new PxRect(0, 0, 1000, 800);
        var f = PinGeometry.InitialFrame(new PxSize(400, 400), 1, vf, new PxRect(980, 780, 10, 10));
        Assert.True(f.X >= vf.X);
        Assert.True(f.Y >= vf.Y);
        Assert.True(f.Right <= vf.Right + 1e-6);
        Assert.True(f.Bottom <= vf.Bottom + 1e-6);
    }

    [Fact]
    public void NonZeroOriginVisibleFrameStillContains()
    {
        var vf = new PxRect(1440, 0, 1920, 1080);
        var f = PinGeometry.InitialFrame(new PxSize(800, 600), 1, vf);
        Assert.True(f.X >= vf.X);
        Assert.True(f.Y >= vf.Y);
        Assert.True(f.Right <= vf.Right + 1e-6);
        Assert.True(f.Bottom <= vf.Bottom + 1e-6);
    }

    [Fact]
    public void ZoomScalesAroundCenter()
    {
        var cur = new PxRect(100, 100, 200, 100);
        var f = PinGeometry.ZoomedFrame(cur, new PxSize(200, 100), 2);
        Assert.Equal(400, f.Width, 6);
        Assert.Equal(200, f.Height, 6);
        Assert.Equal(cur.Center.X, f.Center.X, 6);
        Assert.Equal(cur.Center.Y, f.Center.Y, 6);
    }

    [Fact]
    public void ZoomClampsToMinAndMax()
    {
        var cur = new PxRect(0, 0, 200, 100); // scale 1.0
        Assert.Equal(600, PinGeometry.ZoomedFrame(cur, new PxSize(200, 100), 100).Width, 6); // clamp 3.0
        Assert.Equal(50, PinGeometry.ZoomedFrame(cur, new PxSize(200, 100), 0.001).Width, 6); // clamp 0.25
    }
}
