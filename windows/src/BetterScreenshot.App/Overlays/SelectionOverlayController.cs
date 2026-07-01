using System.Runtime.InteropServices;
using System.Windows.Threading;
using BetterScreenshot.Core;
using BetterScreenshot.Platform;

namespace BetterScreenshot.App.Overlays;

/// <summary>Shows the area-selection overlay on the monitor under the cursor and returns the chosen physical rect.</summary>
public sealed class SelectionOverlayController
{
    /// <summary>
    /// Presents the overlay; <paramref name="completion"/> is invoked (after the overlay is torn down and the screen
    /// repainted) with the selected physical-pixel rect, or null if cancelled.
    /// </summary>
    public void Present(Action<PxRect?> completion)
    {
        var monitor = MonitorUnderCursor();
        var window = new SelectionOverlayWindow(monitor, result =>
        {
            // Defer to Background priority so the (now hidden) overlay is fully gone before the caller captures.
            System.Windows.Application.Current.Dispatcher.BeginInvoke(
                DispatcherPriority.Background, new Action(() => completion(result)));
        });
        window.Show();
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
