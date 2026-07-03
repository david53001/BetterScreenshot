using BetterScreenshot.Recording;
using Xunit;

namespace BetterScreenshot.Tests;

/// <summary>
/// Parsing ffmpeg's <c>-list_devices</c> stderr into dshow device names, and the name heuristics that pick a
/// system-audio loopback device and a microphone. The fixture mirrors real ffmpeg 8.1 output (device lines are
/// <c>"&lt;name&gt;" (audio|video)</c>; each is followed by an "Alternative name" line that must be ignored, and
/// names can contain inner parentheses).
/// </summary>
public class DshowDeviceListTests
{
    private const string Fixture =
        "[in#0 @ 000001] Could not enumerate video devices (or none found).\n" +
        "[in#0 @ 000001] \"Microphone (Yeti Classic)\" (audio)\n" +
        "[in#0 @ 000001]   Alternative name \"@device_cm_{33D9A762}\\wave_{9D7DD97D}\"\n" +
        "[in#0 @ 000001] \"Microphone (Voicemod Virtual Audio Device (WDM))\" (audio)\n" +
        "[in#0 @ 000001]   Alternative name \"@device_cm_{33D9A762}\\wave_{48CF90FD}\"\n" +
        "[in#0 @ 000001] \"HD Webcam C920\" (video)\r\n" +
        "[in#0 @ 000001]   Alternative name \"@device_pnp_\\\\?\\usb\"\n" +
        "Error opening input file dummy.\n";

    [Fact]
    public void Parse_ExtractsAudioAndVideoNames_SkippingAlternativeAndErrorLines()
    {
        var set = DshowDeviceList.Parse(Fixture);

        Assert.Equal(new[]
        {
            "Microphone (Yeti Classic)",
            "Microphone (Voicemod Virtual Audio Device (WDM))", // inner parens preserved
        }, set.Audio);
        Assert.Equal(new[] { "HD Webcam C920" }, set.Video);
    }

    [Fact]
    public void Parse_EmptyOutput_YieldsNoDevices()
    {
        var set = DshowDeviceList.Parse("");
        Assert.Empty(set.Audio);
        Assert.Empty(set.Video);
    }

    [Fact]
    public void PickSystemLoopback_FindsStereoMixClassDevice()
    {
        var audio = new[] { "Microphone (Yeti Classic)", "Stereo Mix (Realtek(R) Audio)", "Line In" };
        Assert.Equal("Stereo Mix (Realtek(R) Audio)", DshowDeviceList.PickSystemLoopback(audio));
    }

    [Fact]
    public void PickSystemLoopback_PrefersStereoMixOverCableOutput()
    {
        var audio = new[] { "CABLE Output (VB-Audio Virtual Cable)", "Stereo Mix" };
        Assert.Equal("Stereo Mix", DshowDeviceList.PickSystemLoopback(audio));
    }

    [Fact]
    public void PickSystemLoopback_ReturnsNull_WhenNoLoopbackClassDevice()
    {
        var audio = new[] { "Microphone (Yeti Classic)", "Chat Mix (Elgato Virtual Audio)" };
        Assert.Null(DshowDeviceList.PickSystemLoopback(audio));
    }

    [Fact]
    public void PickMicrophone_PrefersMicrophoneNamed_ExcludingLoopback()
    {
        var audio = new[] { "Stereo Mix", "Microphone (Yeti Classic)", "Line In" };
        Assert.Equal("Microphone (Yeti Classic)", DshowDeviceList.PickMicrophone(audio, excluding: "Stereo Mix"));
    }

    [Fact]
    public void PickMicrophone_FallsBackToFirstNonExcluded_WhenNoneNamedMicrophone()
    {
        var audio = new[] { "Stereo Mix", "Line In", "Aux" };
        Assert.Equal("Line In", DshowDeviceList.PickMicrophone(audio, excluding: "Stereo Mix"));
    }

    [Fact]
    public void PickMicrophone_ReturnsNull_WhenNothingAvailable()
    {
        Assert.Null(DshowDeviceList.PickMicrophone(new[] { "Stereo Mix" }, excluding: "Stereo Mix"));
    }
}
