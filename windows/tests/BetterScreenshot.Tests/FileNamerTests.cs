using BetterScreenshot.Capture;
using Xunit;

namespace BetterScreenshot.Tests;

public class FileNamerTests
{
    [Fact]
    public void ProducesDeterministicName()
    {
        var d = new DateTime(2026, 6, 2, 14, 32, 10);
        Assert.Equal("Screenshot 2026-06-02 at 14.32.10.png", FileNamer.Name(d, "png"));
    }

    [Fact]
    public void UsesPrefixAndExt()
    {
        var d = new DateTime(1970, 1, 1, 0, 0, 0);
        Assert.Equal("Recording 1970-01-01 at 00.00.00.mp4", FileNamer.Name(d, "mp4", "Recording"));
    }
}
