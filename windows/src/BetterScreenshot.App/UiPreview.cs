using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.App.Editor;
using BetterScreenshot.App.Onboarding;
using BetterScreenshot.App.Overlays;
using BetterScreenshot.App.Recording;
using BetterScreenshot.App.Settings;
using BetterScreenshot.App.Tray;
using BetterScreenshot.Platform;
using Application = System.Windows.Application;
using Color = System.Windows.Media.Color;
using Point = System.Windows.Point;

namespace BetterScreenshot.App;

/// <summary>
/// Dev-only window gallery: `BetterScreenshot.exe --ui-preview &lt;name&gt;` opens one window with sample
/// data and NO tray/hotkeys/single-instance mutex, so the themed UI can be screenshotted (even while a
/// real instance is running). Settings are in-memory defaults — nothing is persisted from a preview.
/// Names: settings (default) | editor | quickaccess | welcome | strip.
/// </summary>
internal static class UiPreview
{
    private sealed class NullCommands : IAppCommands
    {
        public void CaptureArea() { }
        public void CaptureWindow() { }
        public void CaptureFullscreen() { }
        public void CaptureText() { }
        public void ToggleRecording() { }
        public void PauseResumeRecording() { }
        public void PinFromClipboard() { }
        public void OpenHistory() { }
        public void RestoreRecentlyClosed() { }
        public void OpenSettings() { }
        public void Quit() { }
    }

    public static void Show(string name)
    {
        Application.Current.ShutdownMode = ShutdownMode.OnLastWindowClose;
        switch (name)
        {
            case "editor":
                new EditorWindow(SampleImage(900, 560)).Show();
                break;
            case "quickaccess":
                var qa = new QuickAccessWindow(SampleImage(400, 224), QuickAccessKind.Screenshot,
                    new QuickAccessActions(), dragFile: null);
                qa.MoveTo(320, 280);
                qa.Show();
                break;
            case "welcome":
                new WelcomeWindow().Show();
                break;
            case "strip":
                new RecordStripWindow(new SettingsStore()).Show();
                break;
            default: // "settings", "shortcuts" (the Shortcuts card is in the same scroll)
                new SettingsWindow(new SettingsStore(), new HotkeyController(new NullCommands())).Show();
                break;
        }
    }

    /// <summary>A recognizable sample bitmap (diagonal gradient + a light panel) for thumbnails/canvas.</summary>
    private static BitmapSource SampleImage(int width, int height)
    {
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            var gradient = new LinearGradientBrush(
                Color.FromRgb(0x3A, 0x5F, 0x9E), Color.FromRgb(0x7A, 0x4F, 0x8E),
                new Point(0, 0), new Point(1, 1));
            dc.DrawRectangle(gradient, null, new Rect(0, 0, width, height));
            dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(0x66, 0xFF, 0xFF, 0xFF)), null,
                new Rect(width * 0.12, height * 0.18, width * 0.5, height * 0.4), 12, 12);
        }
        var bmp = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        bmp.Render(visual);
        bmp.Freeze();
        return bmp;
    }
}
