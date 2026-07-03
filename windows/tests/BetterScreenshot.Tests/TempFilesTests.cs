using System.IO;
using BetterScreenshot.Platform;
using Xunit;

namespace BetterScreenshot.Tests;

public class TempFilesTests
{
    [Fact]
    public void PayloadLifetimeIsFiveMinutes()
    {
        // The drag/clipboard temp PNG must live exactly 5 minutes — not longer, not shorter.
        Assert.Equal(TimeSpan.FromMinutes(5), TempFiles.PayloadLifetime);
    }

    [Fact]
    public async Task ScheduleDeleteRemovesContainingDirAfterDelay()
    {
        var dir = Path.Combine(Path.GetTempPath(), "bs-tf-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        var file = Path.Combine(dir, "payload.png");
        File.WriteAllText(file, "x");

        TempFiles.ScheduleDeleteContainingDir(file, TimeSpan.FromMilliseconds(150));
        Assert.True(Directory.Exists(dir)); // still present immediately — outlives an in-flight drag

        await Task.Delay(900);
        Assert.False(Directory.Exists(dir)); // and auto-removed once the delay elapses
    }

    [Fact]
    public async Task ScheduleDeleteLeavesSiblingDirsUntouched()
    {
        // Each payload PNG owns its own guid subdir, so deleting one must not touch a sibling
        // (e.g. a capture's separate History copy lives elsewhere entirely and is never in scope).
        var keep = Path.Combine(Path.GetTempPath(), "bs-tf-keep-" + Guid.NewGuid().ToString("N"));
        var drop = Path.Combine(Path.GetTempPath(), "bs-tf-drop-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(keep);
        Directory.CreateDirectory(drop);
        File.WriteAllText(Path.Combine(keep, "history.png"), "keep");
        var dropFile = Path.Combine(drop, "payload.png");
        File.WriteAllText(dropFile, "drop");

        try
        {
            TempFiles.ScheduleDeleteContainingDir(dropFile, TimeSpan.FromMilliseconds(150));
            await Task.Delay(900);

            Assert.False(Directory.Exists(drop)); // the temp payload dir is gone
            Assert.True(Directory.Exists(keep));  // the unrelated dir survives
        }
        finally
        {
            if (Directory.Exists(keep)) Directory.Delete(keep, true);
            if (Directory.Exists(drop)) Directory.Delete(drop, true);
        }
    }

    [Fact]
    public void ScheduleDeleteWithNullOrEmptyIsNoOp()
    {
        // Must not throw for a missing drag file (e.g. a card with no temp payload).
        TempFiles.ScheduleDeleteContainingDir(null, TimeSpan.FromMilliseconds(10));
        TempFiles.ScheduleDeleteContainingDir("", TimeSpan.FromMilliseconds(10));
    }
}
