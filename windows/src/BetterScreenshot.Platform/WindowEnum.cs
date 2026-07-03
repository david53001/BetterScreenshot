using System.Runtime.InteropServices;
using System.Text;
using BetterScreenshot.Capture;
using BetterScreenshot.Core;

namespace BetterScreenshot.Platform;

/// <summary>An enumerated top-level window paired with its native handle (needed later to capture it).</summary>
public readonly record struct EnumeratedWindow(IntPtr Hwnd, PickableWindow Pickable);

/// <summary>
/// Enumerates real, pickable top-level windows in front-to-back Z-order (GetTopWindow + GW_HWNDNEXT), skipping
/// invisible/minimized/cloaked/tool/untitled windows. Frames come from the DWM extended frame bounds so drop
/// shadows are excluded. Feed the resulting <see cref="PickableWindow"/> list to <see cref="WindowPicking.Topmost"/>.
/// </summary>
public static class WindowEnum
{
    private const int GwHwndNext = 2;
    private const int GwlExStyle = -20;
    private const long WsExToolWindow = 0x00000080;
    private const int DwmwaCloaked = 14;
    private const int DwmwaExtendedFrameBounds = 9;

    public static IReadOnlyList<EnumeratedWindow> ForPicking()
    {
        var result = new List<EnumeratedWindow>();
        uint id = 0;

        for (IntPtr h = GetTopWindow(IntPtr.Zero); h != IntPtr.Zero; h = GetWindow(h, GwHwndNext))
        {
            if (!IsWindowVisible(h) || IsIconic(h)) continue;
            if ((GetWindowLongPtr(h, GwlExStyle).ToInt64() & WsExToolWindow) != 0) continue;
            if (DwmGetWindowAttribute(h, DwmwaCloaked, out int cloaked, sizeof(int)) == 0 && cloaked != 0) continue;

            int titleLen = GetWindowTextLength(h);
            if (titleLen == 0) continue; // skip untitled shell windows

            Rect rc;
            if (DwmGetWindowAttribute(h, DwmwaExtendedFrameBounds, out rc, Marshal.SizeOf<Rect>()) != 0)
                GetWindowRect(h, out rc);
            int w = rc.Right - rc.Left, ht = rc.Bottom - rc.Top;
            if (w <= 0 || ht <= 0) continue;

            var sb = new StringBuilder(titleLen + 1);
            GetWindowText(h, sb, sb.Capacity);
            GetWindowThreadProcessId(h, out uint pid);

            var pickable = new PickableWindow(id++, new PxRect(rc.Left, rc.Top, w, ht), sb.ToString(), 0, (int)pid);
            result.Add(new EnumeratedWindow(h, pickable));
        }

        return result;
    }

    /// <summary>
    /// The physical-pixel bounds of a single window (DWM extended frame, shadow excluded; falls back to
    /// <c>GetWindowRect</c>). Used to record a specific window as a fixed desktop region. Null if the handle
    /// is invalid or the window has no area.
    /// </summary>
    public static PxRect? FrameBounds(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return null;
        if (DwmGetWindowAttribute(hwnd, DwmwaExtendedFrameBounds, out Rect rc, Marshal.SizeOf<Rect>()) != 0)
            if (!GetWindowRect(hwnd, out rc)) return null;
        int w = rc.Right - rc.Left, h = rc.Bottom - rc.Top;
        return w > 0 && h > 0 ? new PxRect(rc.Left, rc.Top, w, h) : null;
    }

    [DllImport("user32.dll")] private static extern IntPtr GetTopWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hWnd, int uCmd);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hWnd, out Rect lpRect);
    [DllImport("user32.dll")] private static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex);

    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out int value, int size);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out Rect value, int size);

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect { public int Left, Top, Right, Bottom; }
}
