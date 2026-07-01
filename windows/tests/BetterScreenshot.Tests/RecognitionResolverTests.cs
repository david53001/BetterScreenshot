using BetterScreenshot.Capture;
using Xunit;

namespace BetterScreenshot.Tests;

public class RecognitionResolverTests
{
    [Fact]
    public void QrBeatsText()
    {
        var r = RecognitionResolver.Resolve(new[] { "https://example.com" }, new[] { "hello", "world" });
        Assert.Equal(RecognitionResult.Qr("https://example.com"), r);
    }

    [Fact]
    public void TextLinesJoinWithNewlines()
    {
        var r = RecognitionResolver.Resolve(Array.Empty<string>(), new[] { "hello", "world" });
        Assert.Equal(RecognitionResult.Text("hello\nworld"), r);
    }

    [Fact]
    public void BlankLinesAreDropped()
    {
        var r = RecognitionResolver.Resolve(Array.Empty<string>(), new[] { "", "hello", "" });
        Assert.Equal(RecognitionResult.Text("hello"), r);
    }

    [Fact]
    public void NothingIsNone()
    {
        Assert.Equal(RecognitionResult.None, RecognitionResolver.Resolve(Array.Empty<string>(), Array.Empty<string>()));
        Assert.Equal(RecognitionResult.None, RecognitionResolver.Resolve(Array.Empty<string>(), new[] { "", "" }));
    }

    [Fact]
    public void ClipboardStrings()
    {
        Assert.Equal("x", RecognitionResult.Qr("x").ClipboardString);
        Assert.Equal("y", RecognitionResult.Text("y").ClipboardString);
        Assert.Null(RecognitionResult.None.ClipboardString);
    }

    [Fact]
    public void HudMessages()
    {
        Assert.Equal("QR code copied", RecognitionResult.Qr("x").HudMessage);
        Assert.Equal("Text copied — 4 characters", RecognitionResult.Text("abcd").HudMessage);
        Assert.Equal("No text found", RecognitionResult.None.HudMessage);
    }
}
