namespace BetterScreenshot.App.Tray;

/// <summary>The actions the tray menu (and global hotkeys) invoke. Implemented by the app's coordinator wiring.</summary>
public interface IAppCommands
{
    void CaptureArea();
    void CaptureWindow();
    void CaptureFullscreen();
    void CaptureText();
    void ToggleRecording();
    void PauseResumeRecording();
    void PinFromClipboard();
    void OpenHistory();
    void RestoreRecentlyClosed();
    void OpenSettings();
    void Quit();
}
