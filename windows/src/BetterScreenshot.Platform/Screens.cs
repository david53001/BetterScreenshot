using System.Runtime.InteropServices;
using BetterScreenshot.Core;

namespace BetterScreenshot.Platform;

/// <summary>A physical display: device name, bounds in physical pixels (top-left origin), DPI scale, primary flag.</summary>
public readonly record struct MonitorInfo(string DeviceName, PxRect Bounds, double DpiScale, bool IsPrimary);

/// <summary>Enumerates monitors via Win32 (EnumDisplayMonitors + GetMonitorInfo + GetDpiForMonitor).</summary>
public static class Screens
{
    private const uint MonitorInfoPrimary = 0x1;
    private const int MdtEffectiveDpi = 0;

    public static IReadOnlyList<MonitorInfo> All()
    {
        var result = new List<MonitorInfo>();

        bool Callback(IntPtr hMonitor, IntPtr hdc, ref Rect rc, IntPtr data)
        {
            var mi = new MonitorInfoEx { CbSize = Marshal.SizeOf<MonitorInfoEx>() };
            if (GetMonitorInfo(hMonitor, ref mi))
            {
                double scale = 1.0;
                try
                {
                    if (GetDpiForMonitor(hMonitor, MdtEffectiveDpi, out uint dpiX, out _) == 0 && dpiX > 0)
                        scale = dpiX / 96.0;
                }
                catch (DllNotFoundException)
                {
                    // shcore.dll unavailable (pre-8.1) — leave scale at 1.0.
                }

                var m = mi.Monitor;
                var bounds = new PxRect(m.Left, m.Top, m.Right - m.Left, m.Bottom - m.Top);
                bool primary = (mi.Flags & MonitorInfoPrimary) != 0;
                result.Add(new MonitorInfo(mi.Device, bounds, scale, primary));
            }
            return true; // continue enumeration
        }

        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, Callback, IntPtr.Zero);
        return result;
    }

    /// <summary>The primary monitor (or the first, or a 0×0 fallback if none are present).</summary>
    public static MonitorInfo Primary()
    {
        var all = All();
        foreach (var m in all)
            if (m.IsPrimary) return m;
        return all.Count > 0 ? all[0] : new MonitorInfo(string.Empty, new PxRect(0, 0, 0, 0), 1.0, true);
    }

    private delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, ref Rect lprcMonitor, IntPtr dwData);

    [DllImport("user32.dll")]
    private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool GetMonitorInfo(IntPtr hMonitor, ref MonitorInfoEx lpmi);

    [DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left, Top, Right, Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct MonitorInfoEx
    {
        public int CbSize;
        public Rect Monitor;
        public Rect Work;
        public uint Flags;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string Device;
    }
}
