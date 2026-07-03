using System.Runtime.InteropServices;
using BetterScreenshot.Core;
using BetterScreenshot.Platform;

namespace BetterScreenshot.App.Overlays;

/// <summary>Shared helpers for overlays: the monitor under the cursor and the cursor's physical position.</summary>
internal static class OverlayHelpers
{
    public static MonitorInfo MonitorUnderCursor()
    {
        if (GetCursorPos(out POINT p))
        {
            var cursor = new PxPoint(p.X, p.Y);
            foreach (var m in Screens.All())
                if (m.Bounds.Contains(cursor)) return m;
        }
        return Screens.Primary();
    }

    public static PxPoint CursorPhysical()
    {
        GetCursorPos(out POINT p);
        return new PxPoint(p.X, p.Y);
    }

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out POINT lpPoint);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X, Y; }
}
