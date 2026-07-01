using System.IO;
using System.Windows.Media.Imaging;
using BetterScreenshot.App.Editor;
using BetterScreenshot.App.Overlays;
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
    private readonly SelectionOverlayController _selection = new();
    private readonly QuickAccessStackController _stack = new();
    private readonly PinPanelController _pins = new();
    private readonly WindowPickerController _picker = new();

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
        _picker.Present(hwnd =>
        {
            if (hwnd is { } h && h != IntPtr.Zero) Handle(ScreenCapture.CaptureWindow(h));
        });
    }

    public void CaptureArea()
    {
        _selection.Present(rect =>
        {
            if (rect is { } r) Handle(ScreenCapture.CaptureRegion(r));
        });
    }

    public void CaptureText() => _ = CaptureTextAsync();

    private async Task CaptureTextAsync()
    {
        try
        {
            var image = ScreenCapture.CaptureDisplay(Screens.Primary());
            var result = await TextRecognizerService.RecognizeAsync(image);
            if (result.ClipboardString is { } text) ClipboardService.SetText(text);
            HudController.Show(result.HudMessage);
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
        if (overlay) ShowOverlayCard(image);
    }

    private void ShowOverlayCard(BitmapSource image)
    {
        string dragFile = ImageIo.WriteTempPng(image, "quickaccess.png");
        var actions = new QuickAccessActions
        {
            OnCopy = () => Copy(image),
            OnSave = () => Save(image),
            OnPin = () => PinImage(image),
            OnEdit = () => Annotate(image),
        };
        _stack.Present(image, QuickAccessKind.Screenshot, actions, MapCorner(_settings.Capture.OverlayCorner), dragFile);
    }

    private static Corner MapCorner(SettingsOverlayCorner corner) => corner switch
    {
        SettingsOverlayCorner.TopLeft => Corner.TopLeft,
        SettingsOverlayCorner.TopRight => Corner.TopRight,
        SettingsOverlayCorner.BottomLeft => Corner.BottomLeft,
        _ => Corner.BottomRight,
    };

    private void Save(BitmapSource image)
    {
        bool jpg = _settings.Capture.Format == SettingsImageFormat.Jpg;
        string ext = jpg ? "jpg" : "png";
        string path = Path.Combine(_settings.SaveDirectory, FileNamer.Name(DateTime.Now, ext));
        if (jpg) ImageIo.SaveJpg(image, path); else ImageIo.SavePng(image, path);
    }

    private static void Copy(BitmapSource image) => ClipboardService.SetImage(image);

    public void PinFromClipboard()
    {
        if (System.Windows.Clipboard.ContainsImage())
        {
            var image = System.Windows.Clipboard.GetImage();
            if (image != null) PinImage(image);
        }
    }

    private void PinImage(BitmapSource image)
    {
        var style = new PinStyle(_settings.Capture.PinCornerRadius, _settings.Capture.PinShadow);
        var actions = new PinActions(() => Copy(image), () => Save(image));
        _pins.Pin(image, style, actions);
    }

    /// <summary>Opens the annotation editor on the image, wiring copy/save/stack and sticky-style persistence.</summary>
    private void Annotate(BitmapSource image)
    {
        var editor = new EditorWindow(image, _settings.EditorStyle)
        {
            OnCopy = Copy,
            OnSave = Save,
            OnAddToStack = KeepInStack,
            StyleChanged = style => { _settings.EditorStyle = style; _settings.Save(); },
        };
        editor.Show();
    }

    /// <summary>Editor "Stack" button: re-enter the Quick Access flow (history recording added in Phase 6).</summary>
    private void KeepInStack(BitmapSource image) => ShowOverlayCard(image);

    // Wired up in later phases.
    public void ToggleRecording() { }
    public void PauseResumeRecording() { }
    public void OpenHistory() { }
    public void RestoreRecentlyClosed() { }
    public void OpenSettings() => OnOpenSettings?.Invoke();
    public void Quit() => _quit();
}
