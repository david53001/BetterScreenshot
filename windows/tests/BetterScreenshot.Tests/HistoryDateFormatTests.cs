using BetterScreenshot.History;
using Xunit;

namespace BetterScreenshot.Tests;

public class HistoryDateFormatTests
{
    private static readonly DateTime Now = new(2026, 7, 1, 12, 0, 0, DateTimeKind.Utc);

    [Theory]
    [InlineData(0, "now")]
    [InlineData(30, "now")]
    [InlineData(59, "now")]
    [InlineData(60, "1m ago")]
    [InlineData(2 * 60, "2m ago")]
    [InlineData(59 * 60, "59m ago")]
    [InlineData(60 * 60, "1h ago")]
    [InlineData(2 * 60 * 60, "2h ago")]
    [InlineData(23 * 60 * 60, "23h ago")]
    [InlineData(24 * 60 * 60, "1d ago")]
    [InlineData(6 * 24 * 60 * 60, "6d ago")]
    [InlineData(7 * 24 * 60 * 60, "1w ago")]
    [InlineData(29 * 24 * 60 * 60, "4w ago")]
    public void RelativeUsesAbbreviatedUnits(int secondsAgo, string expected)
    {
        var date = Now.AddSeconds(-secondsAgo);
        Assert.Equal(expected, HistoryDateFormat.Relative(Now, date));
    }

    [Fact]
    public void RelativeUsesMonthsBeyondFourWeeks()
    {
        Assert.Equal("1mo ago", HistoryDateFormat.Relative(Now, Now.AddDays(-31)));
        Assert.Equal("11mo ago", HistoryDateFormat.Relative(Now, Now.AddDays(-340)));
    }

    [Fact]
    public void RelativeUsesYearsBeyondTwelveMonths()
    {
        Assert.Equal("1y ago", HistoryDateFormat.Relative(Now, Now.AddDays(-400)));
    }

    [Fact]
    public void FutureDatesClampToNow()
    {
        Assert.Equal("now", HistoryDateFormat.Relative(Now, Now.AddMinutes(5)));
    }
}
