using System.Runtime.InteropServices;
using System.Windows.Threading;
using BetterScreenshot.Core;
using BetterScreenshot.Platform;

namespace BetterScreenshot.App.Overlays;

/// <summary>
/// Shows the area-selection overlay on every monitor (like the macOS version) and returns the chosen physical rect.
/// The first window to complete or cancel wins and tears the whole set down; presenting again while a selection is
/// open cancels the previous one instead of stacking overlays.
/// </summary>
public sealed class SelectionOverlayController
{
    private List<SelectionOverlayWindow>? _windows;
    private Action<PxRect?>? _completion;

    /// <summary>
    /// Presents the overlay; <paramref name="completion"/> is invoked (after the overlays are torn down and the
    /// screen repainted) with the selected physical-pixel rect, or null if cancelled.
    /// </summary>
    public void Present(Action<PxRect?> completion)
    {
        // Re-entry guard: a second capture hotkey during an open selection cancels it (fires the old
        // completion with null) rather than stacking a second set of dim overlays.
        Cancel();

        _completion = completion;
        var windows = new List<SelectionOverlayWindow>();
        _windows = windows;
        foreach (var m in Screens.All())
            windows.Add(new SelectionOverlayWindow(m, Finish));
        foreach (var w in windows) w.Show();

        // Give keyboard focus (for Escape) to the overlay on the monitor the user is looking at.
        var cursorMonitor = MonitorUnderCursor();
        foreach (var w in windows)
            if (w.Monitor.DeviceName == cursorMonitor.DeviceName) w.ActivateForKeyboard();
    }

    /// <summary>Dismisses an in-flight selection (if any), firing its completion with null.</summary>
    public void Cancel() => Finish(null);

    private void Finish(PxRect? result)
    {
        var completion = _completion;
        var windows = _windows;
        _completion = null;
        _windows = null;
        if (windows != null)
            foreach (var w in windows) w.Dismiss();
        if (completion is null) return;
        // Defer to Background priority so the (now hidden) overlays are fully gone before the caller captures.
        System.Windows.Application.Current.Dispatcher.BeginInvoke(
            DispatcherPriority.Background, new Action(() => completion(result)));
    }

    private static MonitorInfo MonitorUnderCursor()
    {
        if (GetCursorPos(out POINT p))
        {
            var cursor = new PxPoint(p.X, p.Y);
            foreach (var m in Screens.All())
                if (m.Bounds.Contains(cursor)) return m;
        }
        return Screens.Primary();
    }

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out POINT lpPoint);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X, Y; }
}
