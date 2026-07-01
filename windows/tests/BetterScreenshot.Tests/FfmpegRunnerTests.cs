using BetterScreenshot.Platform;
using Xunit;

namespace BetterScreenshot.Tests;

public class FfmpegRunnerTests
{
    [Fact]
    public void ExecutablePathResolves()
    {
        Assert.False(string.IsNullOrWhiteSpace(FfmpegRunner.ExecutablePath));
    }

    [Fact]
    [Trait("category", "hardware")]
    public async Task FfmpegIsAvailableAndRuns()
    {
        Assert.True(FfmpegRunner.IsAvailable(), "ffmpeg must be installed (PATH or bundled)");
        var (ok, _) = await FfmpegRunner.RunAsync(new[] { "-version" });
        Assert.True(ok);
    }
}
