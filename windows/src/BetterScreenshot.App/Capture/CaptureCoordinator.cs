using System.IO;
using System.Windows.Media.Imaging;
using BetterScreenshot.App.Tray;
using BetterScreenshot.Capture;
using BetterScreenshot.Core;
using BetterScreenshot.Platform;

namespace BetterScreenshot.App.Capture;

/// <summary>
/// Orchestrates the screenshot flow: capture (via the Platform layer) → route by the after-capture setting →
/// save/copy. The interactive area-selection overlay, window picker, and Quick Access overlay arrive in Phase 4;
/// until then area falls back to full-screen and the overlay branch saves+copies. Recording/pin/history/settings
/// commands are stubbed until their phases.
/// </summary>
public sealed class CaptureCoordinator : IAppCommands
{
    private readonly SettingsStore _settings;
    private readonly Action _quit;

    public CaptureCoordinator(SettingsStore settings, Action quit)
    {
        _settings = settings;
        _quit = quit;
    }

    /// <summary>Set by the app to show the settings window (which needs the hotkey controller too).</summary>
    public Action? OnOpenSettings { get; set; }

    public void CaptureFullscreen()
    {
        var monitor = Screens.Primary();
        Handle(ScreenCapture.CaptureDisplay(monitor));
    }

    public void CaptureWindow()
    {
        var front = WindowEnum.ForPicking().FirstOrDefault();
        if (front.Hwnd == IntPtr.Zero) { CaptureFullscreen(); return; } // TODO Phase 4: interactive window picker
        Handle(ScreenCapture.CaptureWindow(front.Hwnd));
    }

    public void CaptureArea() => CaptureFullscreen(); // TODO Phase 4: interactive selection overlay

    public void CaptureText() => _ = CaptureTextAsync();

    private async Task CaptureTextAsync()
    {
        try
        {
            var image = ScreenCapture.CaptureDisplay(Screens.Primary());
            var result = await TextRecognizerService.RecognizeAsync(image);
            if (result.ClipboardString is { } text) ClipboardService.SetText(text);
        }
        catch
        {
            // Best-effort; never crash the app on a failed recognition.
        }
    }

    private void Handle(BitmapSource image)
    {
        var (copy, save, overlay) = CaptureRouter.Decide(_settings.Capture.AfterCapture);
        if (copy) Copy(image);
        if (save) Save(image);
        if (overlay)
        {
            // TODO Phase 4: Quick Access overlay. Interim behavior: save + copy so nothing is lost.
            Save(image);
            Copy(image);
        }
    }

    private void Save(BitmapSource image)
    {
        bool jpg = _settings.Capture.Format == SettingsImageFormat.Jpg;
        string ext = jpg ? "jpg" : "png";
        string path = Path.Combine(_settings.SaveDirectory, FileNamer.Name(DateTime.Now, ext));
        if (jpg) ImageIo.SaveJpg(image, path); else ImageIo.SavePng(image, path);
    }

    private static void Copy(BitmapSource image) => ClipboardService.SetImage(image);

    // Wired up in later phases.
    public void ToggleRecording() { }
    public void PauseResumeRecording() { }
    public void PinFromClipboard() { }
    public void OpenHistory() { }
    public void RestoreRecentlyClosed() { }
    public void OpenSettings() => OnOpenSettings?.Invoke();
    public void Quit() => _quit();
}
