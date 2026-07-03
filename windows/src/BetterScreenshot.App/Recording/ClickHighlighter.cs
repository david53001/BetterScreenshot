using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using BetterScreenshot.Core;
using BetterScreenshot.Platform;
using Brushes = System.Windows.Media.Brushes;
using Canvas = System.Windows.Controls.Canvas;
using Color = System.Windows.Media.Color;
using Ellipse = System.Windows.Shapes.Ellipse;

namespace BetterScreenshot.App.Recording;

/// <summary>
/// Flashes a translucent accent circle at each global mouse click while recording (mac <c>ClickHighlighter</c>).
/// A full-primary transparent, click-through overlay window draws a Ø36 accent@0.45 dot at the click point that
/// fades out over 0.4s. Fed by the Platform WH_MOUSE_LL <see cref="MouseHook"/> (its callback runs on this UI thread,
/// since the hook is installed here). Captured because it is an on-screen window.
/// </summary>
public sealed class ClickHighlighter : IDisposable
{
    private ClickOverlayWindow? _window;
    private MouseHook? _hook;

    public void Start()
    {
        _window = new ClickOverlayWindow();
        _window.Show();
        _hook = new MouseHook();
        _hook.MouseDown += OnMouseDown;
    }

    private void OnMouseDown(PxPoint p) => _window?.Flash(p);

    public void Stop()
    {
        if (_hook is not null)
        {
            _hook.MouseDown -= OnMouseDown;
            _hook.Dispose();
            _hook = null;
        }
        _window?.Close();
        _window = null;
    }

    public void Dispose() => Stop();
}

/// <summary>Full-primary transparent, click-through window that draws fading click dots.</summary>
internal sealed class ClickOverlayWindow : Window
{
    private const double Diameter = 36;
    private static readonly Color Accent = Color.FromRgb(0x2F, 0x6F, 0xEB);

    private readonly Canvas _canvas = new();
    private readonly double _scale = Math.Max(0.1, Screens.Primary().DpiScale);

    public ClickOverlayWindow()
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        ShowActivated = false;
        ResizeMode = ResizeMode.NoResize;
        IsHitTestVisible = false;
        Left = 0;
        Top = 0;
        Width = SystemParameters.PrimaryScreenWidth;
        Height = SystemParameters.PrimaryScreenHeight;
        Content = _canvas;
        SourceInitialized += (_, _) => RecordingOverlayInterop.MakeClickThrough(this);
    }

    /// <summary>Draw a fading dot at the given physical-pixel click point (converted to primary-monitor DIPs).</summary>
    public void Flash(PxPoint physical)
    {
        double cx = physical.X / _scale, cy = physical.Y / _scale;
        var dot = new Ellipse
        {
            Width = Diameter,
            Height = Diameter,
            Fill = new SolidColorBrush(Accent),
            IsHitTestVisible = false,
        };
        Canvas.SetLeft(dot, cx - Diameter / 2);
        Canvas.SetTop(dot, cy - Diameter / 2);
        _canvas.Children.Add(dot);

        var fade = new DoubleAnimation(0.45, 0.0, TimeSpan.FromSeconds(0.4));
        fade.Completed += (_, _) => _canvas.Children.Remove(dot);
        dot.BeginAnimation(OpacityProperty, fade);
    }
}

/// <summary>Makes a WPF overlay window click-through (WS_EX_TRANSPARENT | LAYERED | TOOLWINDOW) so it never grabs input.</summary>
internal static class RecordingOverlayInterop
{
    private const int GwlExStyle = -20;
    private const int WsExTransparent = 0x20, WsExLayered = 0x80000, WsExToolWindow = 0x80;

    public static void MakeClickThrough(Window window)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        if (hwnd == IntPtr.Zero) return;
        int ex = GetWindowLong(hwnd, GwlExStyle);
        SetWindowLong(hwnd, GwlExStyle, ex | WsExTransparent | WsExLayered | WsExToolWindow);
    }

    [DllImport("user32.dll")] private static extern int GetWindowLong(IntPtr hwnd, int index);
    [DllImport("user32.dll")] private static extern int SetWindowLong(IntPtr hwnd, int index, int newLong);
}
