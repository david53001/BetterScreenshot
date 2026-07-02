using System.Windows;
using BetterScreenshot.App.Capture;
using BetterScreenshot.App.Onboarding;
using BetterScreenshot.App.Settings;
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
    private CaptureCoordinator _commands = null!;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        _settings = SettingsStore.Load();
        _commands = new CaptureCoordinator(_settings, Shutdown);
        _tray = new TrayIcon(_commands, _settings.Hotkeys);
        _hotkeys = new HotkeyController(_commands);
        _hotkeys.Apply(_settings.Hotkeys);
        _commands.OnOpenSettings = ShowSettings;
        _commands.OnRecordingStateChanged = _tray.SetRecordingState;
        _commands.OnRecordingPauseChanged = _tray.SetPauseState;

        if (!_settings.FirstRunComplete)
        {
            new WelcomeWindow().ShowDialog();
            _settings.FirstRunComplete = true;
            _settings.Save();
        }
    }

    private SettingsWindow? _settingsWindow;

    private void ShowSettings()
    {
        if (_settingsWindow != null) { _settingsWindow.Activate(); return; }
        _settingsWindow = new SettingsWindow(_settings, _hotkeys);
        _settingsWindow.Closed += (_, _) => _settingsWindow = null;
        _settingsWindow.Show();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _commands?.StopRecordingForExit(); // best-effort finalize an in-progress recording before we tear down
        _hotkeys?.Dispose();
        _tray?.Dispose();
        base.OnExit(e);
    }
}
