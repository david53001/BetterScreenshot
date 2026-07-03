using BetterScreenshot.Capture;
using BetterScreenshot.Core;
using Xunit;

namespace BetterScreenshot.Tests;

public class WindowPickingTests
{
    private static readonly PxPoint Hit = new(50, 50);

    [Fact]
    public void TopmostReturnsFrontOnOverlap()
    {
        var front = new PickableWindow(1, new PxRect(0, 0, 100, 100), "front", 0, 7);
        var back = new PickableWindow(2, new PxRect(0, 0, 500, 500), "back", 0, 7);
        var w = WindowPicking.Topmost(Hit, new[] { front, back }, excludePid: 999);
        Assert.Equal(1u, w!.Value.Id);
    }

    [Fact]
    public void SkipsNonNormalLayer()
    {
        var menu = new PickableWindow(1, new PxRect(0, 0, 100, 100), "menu", 25, 7);
        var app = new PickableWindow(2, new PxRect(0, 0, 100, 100), "app", 0, 7);
        var w = WindowPicking.Topmost(Hit, new[] { menu, app }, excludePid: 999);
        Assert.Equal(2u, w!.Value.Id);
    }

    [Fact]
    public void ExcludesOwnPid()
    {
        var own = new PickableWindow(1, new PxRect(0, 0, 100, 100), "own", 0, 42);
        var other = new PickableWindow(2, new PxRect(0, 0, 100, 100), "other", 0, 7);
        var w = WindowPicking.Topmost(Hit, new[] { own, other }, excludePid: 42);
        Assert.Equal(2u, w!.Value.Id);
    }

    [Fact]
    public void MissReturnsNull()
    {
        var win = new PickableWindow(1, new PxRect(0, 0, 10, 10), "small", 0, 7);
        Assert.Null(WindowPicking.Topmost(new PxPoint(500, 500), new[] { win }, excludePid: 999));
    }
}
