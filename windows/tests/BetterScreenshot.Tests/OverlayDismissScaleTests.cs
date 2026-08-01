using BetterScreenshot.Capture;
using Xunit;

namespace BetterScreenshot.Tests;

public class OverlayDismissScaleTests
{
    [Fact]
    public void Stop_table_spans_30_seconds_to_30_minutes()
    {
        Assert.Equal(new[] { 30, 60, 120, 300, 600, 900, 1800 }, OverlayDismissScale.FiniteStops);
        Assert.Equal(7, OverlayDismissScale.NeverPosition);
    }

    [Theory]
    [InlineData(0, 7)]      // Never (persisted as 0) -> the far ("Never") end of the bar
    [InlineData(-5, 7)]     // any non-positive value is treated as Never
    [InlineData(30, 0)]     // shortest stop
    [InlineData(300, 3)]    // 5m
    [InlineData(1800, 6)]   // longest finite stop
    [InlineData(6, 0)]      // legacy default snaps up to the 30s stop
    [InlineData(9999, 6)]   // beyond the table clamps to 30m
    public void SecondsToPosition_maps_and_snaps(int seconds, int expectedPosition) =>
        Assert.Equal(expectedPosition, OverlayDismissScale.SecondsToPosition(seconds));

    [Theory]
    [InlineData(7, 0)]      // far end -> Never
    [InlineData(7.4, 0)]    // anything at/after the Never stop -> Never
    [InlineData(0, 30)]
    [InlineData(3, 300)]
    [InlineData(6, 1800)]
    [InlineData(2.4, 120)]  // rounds to the nearest stop index
    [InlineData(-1, 30)]    // below the table clamps up (defensive; the slider never goes here)
    public void PositionToSeconds_maps_rounds_and_clamps(double position, int expectedSeconds) =>
        Assert.Equal(expectedSeconds, OverlayDismissScale.PositionToSeconds(position));

    [Theory]
    [InlineData(0, 0)]      // Never stays Never
    [InlineData(-3, 0)]
    [InlineData(6, 30)]     // the pre-2.5 default
    [InlineData(1, 30)]
    [InlineData(50, 60)]
    [InlineData(45, 30)]    // tie breaks toward the shorter stop
    [InlineData(9999, 1800)]
    public void Snap_rounds_to_nearest_stop(int seconds, int expected) =>
        Assert.Equal(expected, OverlayDismissScale.Snap(seconds));

    [Theory]
    [InlineData(0, "Never")]
    [InlineData(-1, "Never")]
    [InlineData(30, "30s")]
    [InlineData(60, "1m")]
    [InlineData(300, "5m")]
    [InlineData(1800, "30m")]
    public void Label_reads_never_seconds_or_minutes(int seconds, string expected) =>
        Assert.Equal(expected, OverlayDismissScale.Label(seconds));

    [Theory]
    [InlineData(0)]  // Never survives a position round-trip
    [InlineData(30)]
    [InlineData(60)]
    [InlineData(120)]
    [InlineData(300)]
    [InlineData(600)]
    [InlineData(900)]
    [InlineData(1800)]
    public void RoundTrips_through_position(int seconds) =>
        Assert.Equal(seconds, OverlayDismissScale.PositionToSeconds(OverlayDismissScale.SecondsToPosition(seconds)));
}
