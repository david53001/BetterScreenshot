using BetterScreenshot.App.Tray;
using BetterScreenshot.Capture;
using BetterScreenshot.Platform;

namespace BetterScreenshot.App;

/// <summary>
/// Bridges global hotkeys to app commands: registers the current bindings on a <see cref="HotkeyHost"/> and routes
/// each fired action to the matching <see cref="IAppCommands"/> method. Re-apply on binding changes; suspend/resume
/// around the shortcut recorder.
/// </summary>
public sealed class HotkeyController : IDisposable
{
    private readonly HotkeyHost _host;
    private readonly IAppCommands _commands;

    public IReadOnlySet<HotkeyAction> FailedRegistrations { get; private set; } = new HashSet<HotkeyAction>();

    public HotkeyController(IAppCommands commands)
    {
        _commands = commands;
        _host = new HotkeyHost();
        _host.HotkeyPressed += OnHotkeyPressed;
    }

    public void Apply(HotkeyBindings bindings) => FailedRegistrations = _host.Apply(bindings.Bound);

    public void Suspend() => _host.Suspend();
    public void Resume() => _host.Resume();

    private void OnHotkeyPressed(HotkeyAction action) => Dispatch(action, _commands);

    /// <summary>Pure routing of an action to its command (unit-testable without the hotkey host).</summary>
    public static void Dispatch(HotkeyAction action, IAppCommands commands)
    {
        switch (action)
        {
            case HotkeyAction.CaptureArea: commands.CaptureArea(); break;
            case HotkeyAction.CaptureWindow: commands.CaptureWindow(); break;
            case HotkeyAction.CaptureFullscreen: commands.CaptureFullscreen(); break;
            case HotkeyAction.CaptureText: commands.CaptureText(); break;
            case HotkeyAction.Record: commands.ToggleRecording(); break;
            case HotkeyAction.PauseResumeRecording: commands.PauseResumeRecording(); break;
            case HotkeyAction.PinFromClipboard: commands.PinFromClipboard(); break;
            case HotkeyAction.OpenHistory: commands.OpenHistory(); break;
            case HotkeyAction.RestoreRecentlyClosed: commands.RestoreRecentlyClosed(); break;
        }
    }

    public void Dispose()
    {
        _host.HotkeyPressed -= OnHotkeyPressed;
        _host.Dispose();
    }
}
