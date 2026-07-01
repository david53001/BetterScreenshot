using System.Windows;

namespace BetterScreenshot.App;

/// <summary>
/// Application entry point. BetterScreenshot is a tray agent: it has no main window and stays alive
/// until the user quits from the tray menu (ShutdownMode = OnExplicitShutdown). The tray shell,
/// hotkeys, and coordinators are wired up in OnStartup (Phase 3).
/// </summary>
public partial class App : System.Windows.Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        // Phase 3 wires TrayIcon + HotkeyController + coordinators here.
    }
}
