using System.Windows;
using BetterScreenshot.App.Tray;
using BetterScreenshot.Platform;

namespace BetterScreenshot.App;

/// <summary>
/// Application entry point. BetterScreenshot is a tray agent: it has no main window and stays alive
/// until the user quits from the tray menu (ShutdownMode = OnExplicitShutdown). Later Phase-3 tasks wire the
/// hotkey host and the real capture/recording coordinators into the command surface.
/// </summary>
public partial class App : System.Windows.Application
{
    private SettingsStore _settings = null!;
    private TrayIcon _tray = null!;
    private HotkeyController _hotkeys = null!;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        _settings = SettingsStore.Load();
        var commands = new StubCommands(this);
        _tray = new TrayIcon(commands, _settings.Hotkeys);
        _hotkeys = new HotkeyController(commands);
        _hotkeys.Apply(_settings.Hotkeys);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _hotkeys?.Dispose();
        _tray?.Dispose();
        base.OnExit(e);
    }

    /// <summary>Temporary command target so the app is runnable now; replaced by the coordinator wiring in Task 3.4/7.2.</summary>
    private sealed class StubCommands(App app) : IAppCommands
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
        public void Quit() => app.Shutdown();
    }
}
