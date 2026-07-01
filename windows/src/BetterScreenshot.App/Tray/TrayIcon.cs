using System.Drawing;
using BetterScreenshot.App.Branding;
using BetterScreenshot.Capture;
using WF = System.Windows.Forms;

namespace BetterScreenshot.App.Tray;

/// <summary>
/// The system-tray presence (macOS menu-bar equivalent): a WinForms <see cref="WF.NotifyIcon"/> with the full
/// context menu. Swaps to a red icon + elapsed tooltip while recording, and toggles the Record/Pause menu items.
/// </summary>
public sealed class TrayIcon : IDisposable
{
    private readonly WF.NotifyIcon _notify;
    private readonly Icon _normalIcon;
    private readonly Icon _recordingIcon;
    private readonly WF.ToolStripMenuItem _recordItem;
    private readonly WF.ToolStripMenuItem _pauseResumeItem;

    public TrayIcon(IAppCommands commands, HotkeyBindings bindings)
    {
        _normalIcon = AppIconFactory.CreateTrayIcon(recording: false);
        _recordingIcon = AppIconFactory.CreateTrayIcon(recording: true);

        _recordItem = Item("Record Screen…", bindings.Combo(HotkeyAction.Record)?.DisplayString, commands.ToggleRecording);
        _pauseResumeItem = Item("Pause Recording", bindings.Combo(HotkeyAction.PauseResumeRecording)?.DisplayString, commands.PauseResumeRecording);
        _pauseResumeItem.Visible = false;

        var menu = new WF.ContextMenuStrip();
        menu.Items.AddRange(new WF.ToolStripItem[]
        {
            Item("Capture Area", bindings.Combo(HotkeyAction.CaptureArea)?.DisplayString, commands.CaptureArea),
            Item("Capture Window", bindings.Combo(HotkeyAction.CaptureWindow)?.DisplayString, commands.CaptureWindow),
            Item("Capture Fullscreen", bindings.Combo(HotkeyAction.CaptureFullscreen)?.DisplayString, commands.CaptureFullscreen),
            Item("Capture Text", bindings.Combo(HotkeyAction.CaptureText)?.DisplayString, commands.CaptureText),
            new WF.ToolStripSeparator(),
            _recordItem,
            _pauseResumeItem,
            new WF.ToolStripSeparator(),
            Item("Pin from Clipboard", bindings.Combo(HotkeyAction.PinFromClipboard)?.DisplayString, commands.PinFromClipboard),
            new WF.ToolStripSeparator(),
            Item("History…", bindings.Combo(HotkeyAction.OpenHistory)?.DisplayString, commands.OpenHistory),
            Item("Restore Recently Closed", bindings.Combo(HotkeyAction.RestoreRecentlyClosed)?.DisplayString, commands.RestoreRecentlyClosed),
            new WF.ToolStripSeparator(),
            Item("Settings…", null, commands.OpenSettings),
            Item("Quit", null, commands.Quit),
        });

        _notify = new WF.NotifyIcon
        {
            Icon = _normalIcon,
            Visible = true,
            Text = "BetterScreenshot",
            ContextMenuStrip = menu,
        };
        // Left-click opens the menu too (like the macOS menu-bar item).
        _notify.MouseClick += (_, e) =>
        {
            if (e.Button == WF.MouseButtons.Left) ShowMenu(menu);
        };
    }

    public void SetRecordingState(bool recording, string? elapsed)
    {
        _notify.Icon = recording ? _recordingIcon : _normalIcon;
        _notify.Text = recording ? Trim($"BetterScreenshot — {elapsed}") : "BetterScreenshot";
        _recordItem.Text = recording ? "Stop Recording" : "Record Screen…";
        _pauseResumeItem.Visible = recording;
    }

    private static void ShowMenu(WF.ContextMenuStrip menu)
    {
        menu.Show(WF.Cursor.Position);
    }

    private static WF.ToolStripMenuItem Item(string text, string? shortcut, Action onClick)
    {
        var item = new WF.ToolStripMenuItem(text);
        if (!string.IsNullOrEmpty(shortcut)) item.ShortcutKeyDisplayString = shortcut;
        item.Click += (_, _) => onClick();
        return item;
    }

    // NotifyIcon.Text has a 63-char limit.
    private static string Trim(string s) => s.Length <= 63 ? s : s[..63];

    public void Dispose()
    {
        _notify.Visible = false;
        _notify.Dispose();
        _normalIcon.Dispose();
        _recordingIcon.Dispose();
    }
}
