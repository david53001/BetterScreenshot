using BetterScreenshot.Core;
using BetterScreenshot.Recording;
using Xunit;

namespace BetterScreenshot.Tests;

public class RecordingConfigTests
{
    [Fact]
    public void DefaultsRoundTrip()
    {
        var round = RecordingConfig.FromDictionary(RecordingConfig.Default.ToDictionary());
        Assert.Equal(RecordingConfig.Default, round);
    }

    [Fact]
    public void AllFieldsRoundTrip()
    {
        var c = RecordingConfig.Default with
        {
            Format = RecordingFormat.Gif,
            Fps = 60,
            SystemAudio = false,
            Microphone = true,
            Camera = true,
            CameraSize = CameraSize.Medium,
            ClickHighlights = false,
            KeystrokeOverlay = true,
            CountdownSeconds = 5,
        };
        Assert.Equal(c, RecordingConfig.FromDictionary(c.ToDictionary()));
    }

    [Theory]
    [InlineData("45", 30)]
    [InlineData("30", 30)]
    [InlineData("60", 60)]
    public void FpsClampsToAllowedValues(string raw, int expected)
    {
        var d = RecordingConfig.Default.ToDictionary();
        d["fps"] = raw;
        Assert.Equal(expected, RecordingConfig.FromDictionary(d).Fps);
    }

    [Theory]
    [InlineData("7", 0)]
    [InlineData("3", 3)]
    [InlineData("10", 10)]
    public void CountdownClampsToAllowedValues(string raw, int expected)
    {
        var d = RecordingConfig.Default.ToDictionary();
        d["countdownSeconds"] = raw;
        Assert.Equal(expected, RecordingConfig.FromDictionary(d).CountdownSeconds);
    }

    [Fact]
    public void VideoBitrate()
    {
        var c = RecordingConfig.Default; // 30fps
        Assert.Equal(7_464_960L, c.VideoBitrate(1920, 1080));
        Assert.Equal(2_000_000L, c.VideoBitrate(100, 100)); // clamped up to floor
    }

    [Fact]
    public void CameraDiameters()
    {
        Assert.Equal(160, CameraSize.Small.Diameter());
        Assert.Equal(240, CameraSize.Medium.Diameter());
    }
}

public class RecorderStateTests
{
    private static readonly DateTime T0 = new(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);

    [Fact]
    public void LegalLifecycle()
    {
        var s = RecorderState.Idle;
        Assert.True(s.Transition(RecorderEvent.Arm));
        Assert.True(s.Transition(RecorderEvent.Begin, T0));
        Assert.True(s.Transition(RecorderEvent.Finish));
        Assert.True(s.Transition(RecorderEvent.Reset));
        Assert.Equal(RecorderPhase.Idle, s.Phase);
    }

    [Fact]
    public void IllegalTransitionsRejected()
    {
        var s = RecorderState.Idle;
        Assert.False(s.Transition(RecorderEvent.Pause));
        Assert.False(s.Transition(RecorderEvent.Resume));
        Assert.False(s.Transition(RecorderEvent.Begin));
        s.Transition(RecorderEvent.Arm);
        Assert.False(s.Transition(RecorderEvent.Pause));
    }

    [Fact]
    public void ElapsedExcludesPause()
    {
        var s = RecorderState.Idle;
        s.Transition(RecorderEvent.Arm);
        s.Transition(RecorderEvent.Begin, T0);
        s.Transition(RecorderEvent.Pause, T0.AddSeconds(10));
        Assert.Equal("Paused · 0:10", s.ElapsedString(T0.AddSeconds(12)));
        s.Transition(RecorderEvent.Resume, T0.AddSeconds(13)); // 3s paused
        Assert.Equal("0:17", s.ElapsedString(T0.AddSeconds(20))); // 20 - 0 - 3
    }
}

public class PauseTimelineTests
{
    [Fact]
    public void ZeroOffsetByDefault()
    {
        var t = new PauseTimeline();
        Assert.Equal(0, t.Offset);
        Assert.Equal(123, t.Adjusted(123));
    }

    [Fact]
    public void SinglePauseIsContiguous()
    {
        var t = new PauseTimeline();
        t.Resume(lastPtsBeforePause: 100, firstPtsAfterResume: 150, frameDuration: 10);
        Assert.Equal(40, t.Offset);
        Assert.Equal(110, t.Adjusted(150)); // one frame after 100
    }

    [Fact]
    public void MultiplePausesAccumulate()
    {
        var t = new PauseTimeline();
        t.Resume(100, 150, 10); // +40
        t.Resume(200, 260, 10); // +50
        Assert.Equal(90, t.Offset);
    }

    [Fact]
    public void NonPositiveGapIgnored()
    {
        var t = new PauseTimeline();
        t.Resume(100, 108, 10); // gap = -2 → ignored
        Assert.Equal(0, t.Offset);
    }
}

public class GIFTimingTests
{
    [Fact]
    public void FrameTimesCountAndBounds()
    {
        var times = GIFTiming.FrameTimes(2.5, 10);
        Assert.Equal(25, times.Count);
        Assert.Equal(0.0, times[0], 6);
        Assert.Equal(2.4, times[24], 6);
    }

    [Fact]
    public void OutputSizeDownscalesButNeverUpscales()
    {
        Assert.Equal(new PxSize(960, 540), GIFTiming.OutputSize(new PxSize(1920, 1080), 960));
        Assert.Equal(new PxSize(800, 600), GIFTiming.OutputSize(new PxSize(800, 600), 960));
    }
}
