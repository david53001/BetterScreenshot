using BetterScreenshot.Editor;
using Xunit;

namespace BetterScreenshot.Tests;

public class EditorStyleTests
{
    [Fact]
    public void ColorComponentsAndAlpha()
    {
        var c = new RGBAColor(1.0, 0.5, 0.25, 1.0);
        Assert.Equal(1.0, c.R);
        Assert.Equal(0.5, c.G);
        Assert.Equal(0.25, c.B);
        Assert.Equal(0.25, c.WithAlpha(0.25).A);
        Assert.Equal(new RGBAColor(1, 1, 1, 1), RGBAColor.FromBytes(255, 255, 255));
    }

    [Fact]
    public void DefaultStyleIsRed()
    {
        var d = AnnotationStyle.Default;
        Assert.Equal(new RGBAColor(1.0, 0.23, 0.19, 1.0), d.StrokeColor);
        Assert.Equal(0.25, d.FillColor.A);
        Assert.Equal(4, d.LineWidth);
        Assert.Equal(24, d.FontSize);
    }

    [Fact]
    public void RoundTripsThroughJson()
    {
        var s = AnnotationStyle.Default with
        {
            StrokeColor = new RGBAColor(0.04, 0.52, 1.0, 1.0),
            LineWidth = 7,
            FontSize = 36,
        };
        Assert.Equal(s, AnnotationStyle.FromJson(s.ToJson()));
    }

    [Fact]
    public void TextBackgroundDefaultsToNullAndRoundTrips()
    {
        Assert.Null(AnnotationStyle.Default.TextBackground);

        var withBg = AnnotationStyle.Default with { TextBackground = new RGBAColor(0, 0, 0, 0.6) };
        Assert.Equal(withBg, AnnotationStyle.FromJson(withBg.ToJson()));
    }

    [Fact]
    public void LegacyJsonWithoutTextBackgroundDeserializesToNull()
    {
        // A style persisted before TextBackground existed must still load (field absent -> null), so an existing
        // UserDefaults/editorStyle value never breaks the editor.
        const string legacy = "{\"strokeColor\":{\"r\":1,\"g\":0.23,\"b\":0.19,\"a\":1}," +
                              "\"fillColor\":{\"r\":1,\"g\":0.23,\"b\":0.19,\"a\":0.25},\"lineWidth\":4,\"fontSize\":24}";
        Assert.Null(AnnotationStyle.FromJson(legacy).TextBackground);
    }
}
