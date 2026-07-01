using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media.Imaging;
using BetterScreenshot.Core;

namespace BetterScreenshot.Platform;

/// <summary>
/// Still screen capture via GDI. <see cref="CaptureRegion"/>/<see cref="CaptureDisplay"/> BitBlt a rectangle of
/// the virtual desktop; <see cref="CaptureWindow"/> uses PrintWindow (full-content) so occluded windows still
/// capture. All coordinates are physical pixels, top-left origin. Returns frozen <see cref="BitmapSource"/>s.
/// </summary>
public static class ScreenCapture
{
    private const int Srccopy = 0x00CC0020;
    private const int Captureblt = 0x40000000;
    private const uint PwRenderFullContent = 0x00000002;

    public static BitmapSource CaptureRegion(PxRect region)
    {
        int x = (int)Math.Round(region.X);
        int y = (int)Math.Round(region.Y);
        int w = Math.Max(1, (int)Math.Round(region.Width));
        int h = Math.Max(1, (int)Math.Round(region.Height));

        IntPtr screenDc = GetDC(IntPtr.Zero);
        IntPtr memDc = CreateCompatibleDC(screenDc);
        IntPtr hBmp = CreateCompatibleBitmap(screenDc, w, h);
        IntPtr old = SelectObject(memDc, hBmp);
        try
        {
            BitBlt(memDc, 0, 0, w, h, screenDc, x, y, Srccopy | Captureblt);
            return ToBitmapSource(hBmp);
        }
        finally
        {
            SelectObject(memDc, old);
            DeleteObject(hBmp);
            DeleteDC(memDc);
            ReleaseDC(IntPtr.Zero, screenDc);
        }
    }

    public static BitmapSource CaptureDisplay(MonitorInfo monitor) => CaptureRegion(monitor.Bounds);

    public static BitmapSource CaptureWindow(IntPtr hwnd)
    {
        GetWindowRect(hwnd, out Rect r);
        int w = Math.Max(1, r.Right - r.Left);
        int h = Math.Max(1, r.Bottom - r.Top);

        IntPtr screenDc = GetDC(IntPtr.Zero);
        IntPtr memDc = CreateCompatibleDC(screenDc);
        IntPtr hBmp = CreateCompatibleBitmap(screenDc, w, h);
        IntPtr old = SelectObject(memDc, hBmp);
        try
        {
            if (!PrintWindow(hwnd, memDc, PwRenderFullContent))
                BitBlt(memDc, 0, 0, w, h, screenDc, r.Left, r.Top, Srccopy | Captureblt); // fallback for older windows
            return ToBitmapSource(hBmp);
        }
        finally
        {
            SelectObject(memDc, old);
            DeleteObject(hBmp);
            DeleteDC(memDc);
            ReleaseDC(IntPtr.Zero, screenDc);
        }
    }

    private static BitmapSource ToBitmapSource(IntPtr hBmp)
    {
        var src = Imaging.CreateBitmapSourceFromHBitmap(hBmp, IntPtr.Zero, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
        src.Freeze();
        return src;
    }

    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDc);
    [DllImport("user32.dll")] private static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint nFlags);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hWnd, out Rect lpRect);

    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleDC(IntPtr hDc);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleBitmap(IntPtr hDc, int w, int h);
    [DllImport("gdi32.dll")] private static extern IntPtr SelectObject(IntPtr hDc, IntPtr hObject);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr hObject);
    [DllImport("gdi32.dll")] private static extern bool DeleteDC(IntPtr hDc);
    [DllImport("gdi32.dll")] private static extern bool BitBlt(IntPtr hDc, int x, int y, int w, int h, IntPtr hSrcDc, int xSrc, int ySrc, int rop);

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect { public int Left, Top, Right, Bottom; }
}
