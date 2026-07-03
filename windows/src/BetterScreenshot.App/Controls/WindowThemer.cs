using System.Runtime.InteropServices;
using System.Windows.Interop;
using Window = System.Windows.Window;

namespace BetterScreenshot.App.Controls;

/// <summary>Darkens the DWM title bar of titled windows (Settings/Editor/History/Welcome). Safe no-op
/// when the attribute is unsupported (pre-20H1) — the window just keeps a light title bar.</summary>
public static class WindowThemer
{
    private const int DwmwaUseImmersiveDarkMode = 20;

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    public static void ApplyDark(Window window)
    {
        if (new WindowInteropHelper(window).Handle != IntPtr.Zero) Apply(window);
        else window.SourceInitialized += (_, _) => Apply(window);
    }

    private static void Apply(Window window)
    {
        try
        {
            int on = 1;
            _ = DwmSetWindowAttribute(new WindowInteropHelper(window).Handle,
                DwmwaUseImmersiveDarkMode, ref on, sizeof(int));
        }
        catch (DllNotFoundException) { }
        catch (EntryPointNotFoundException) { }
    }
}
