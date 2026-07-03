using BetterScreenshot.App;
using BetterScreenshot.App.Tray;
using BetterScreenshot.Capture;
using Xunit;

namespace BetterScreenshot.Tests;

public class HotkeyControllerTests
{
    private sealed class RecordingCommands : IAppCommands
    {
        public string? Last;
        public void CaptureArea() => Last = nameof(CaptureArea);
        public void CaptureWindow() => Last = nameof(CaptureWindow);
        public void CaptureFullscreen() => Last = nameof(CaptureFullscreen);
        public void CaptureText() => Last = nameof(CaptureText);
        public void ToggleRecording() => Last = nameof(ToggleRecording);
        public void PauseResumeRecording() => Last = nameof(PauseResumeRecording);
        public void PinFromClipboard() => Last = nameof(PinFromClipboard);
        public void OpenHistory() => Last = nameof(OpenHistory);
        public void RestoreRecentlyClosed() => Last = nameof(RestoreRecentlyClosed);
        public void OpenSettings() => Last = nameof(OpenSettings);
        public void Quit() => Last = nameof(Quit);
    }

    [Theory]
    [InlineData(HotkeyAction.CaptureArea, "CaptureArea")]
    [InlineData(HotkeyAction.CaptureWindow, "CaptureWindow")]
    [InlineData(HotkeyAction.CaptureFullscreen, "CaptureFullscreen")]
    [InlineData(HotkeyAction.CaptureText, "CaptureText")]
    [InlineData(HotkeyAction.Record, "ToggleRecording")]
    [InlineData(HotkeyAction.PauseResumeRecording, "PauseResumeRecording")]
    [InlineData(HotkeyAction.PinFromClipboard, "PinFromClipboard")]
    [InlineData(HotkeyAction.OpenHistory, "OpenHistory")]
    [InlineData(HotkeyAction.RestoreRecentlyClosed, "RestoreRecentlyClosed")]
    public void DispatchRoutesActionToCommand(HotkeyAction action, string expected)
    {
        var commands = new RecordingCommands();
        HotkeyController.Dispatch(action, commands);
        Assert.Equal(expected, commands.Last);
    }
}
