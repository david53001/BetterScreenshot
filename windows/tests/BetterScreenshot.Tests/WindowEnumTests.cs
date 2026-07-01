using BetterScreenshot.Capture;
using BetterScreenshot.Platform;
using Xunit;

namespace BetterScreenshot.Tests;

public class WindowEnumTests
{
    [Fact]
    [Trait("category", "hardware")]
    public void EnumeratesWindowsWithUniqueIdsAndValidFrames()
    {
        var wins = WindowEnum.ForPicking();
        Assert.NotNull(wins);

        var ids = new HashSet<uint>();
        foreach (var w in wins)
        {
            Assert.NotEqual(IntPtr.Zero, w.Hwnd);
            Assert.Equal(0, w.Pickable.Layer);
            Assert.True(w.Pickable.Frame.Width > 0);
            Assert.True(w.Pickable.Frame.Height > 0);
            Assert.True(ids.Add(w.Pickable.Id), "window ids must be unique within an enumeration");
        }

        // The enumerated list must be usable by the pure hit-tester without throwing.
        var pickables = wins.Select(w => w.Pickable).ToList();
        _ = WindowPicking.Topmost(new BetterScreenshot.Core.PxPoint(0, 0), pickables, excludePid: -1);
    }
}
