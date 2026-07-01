using System.Windows;
using BetterScreenshot.App.Capture;
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
        var commands = new CaptureCoordinator(_settings, Shutdown);
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
}
