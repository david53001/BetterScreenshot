using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using BetterScreenshot.Capture;
using BetterScreenshot.Core;
using BetterScreenshot.Platform;
using Canvas = System.Windows.Controls.Canvas;
using Color = System.Windows.Media.Color;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using MouseButtonEventArgs = System.Windows.Input.MouseButtonEventArgs;
using MouseEventArgs = System.Windows.Input.MouseEventArgs;
using SolidColorBrush = System.Windows.Media.SolidColorBrush;

namespace BetterScreenshot.App.Overlays;

/// <summary>
/// Full-monitor overlay for interactive window picking: highlights the window under the cursor (accent fill + 3px
/// stroke + title caption) using the tested <see cref="WindowPicking.Topmost"/>; click picks, Esc cancels. Reports
/// the chosen HWND (or null). Positioned in physical pixels via MoveWindow for per-monitor DPI correctness.
/// </summary>
public partial class WindowPickerWindow : Window
{
    private readonly MonitorInfo _monitor;
    private readonly Action<IntPtr?> _onPicked;
    private IReadOnlyList<EnumeratedWindow> _windows = Array.Empty<EnumeratedWindow>();
    private EnumeratedWindow? _hovered;
    private bool _done;

    public WindowPickerWindow(MonitorInfo monitor, Action<IntPtr?> onPicked)
    {
        _monitor = monitor;
        _onPicked = onPicked;
        InitializeComponent();

        var accent = Color.FromRgb(0x0A, 0x84, 0xFF);
        Highlight.Fill = new SolidColorBrush(accent) { Opacity = 0.18 };
        Highlight.Stroke = new SolidColorBrush(accent);
        Highlight.StrokeThickness = 3;

        SourceInitialized += OnInit;
        MouseMove += OnMove;
        MouseLeftButtonUp += OnUp;
        KeyDown += OnKey;
    }

    private void OnInit(object? sender, EventArgs e)
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        var b = _monitor.Bounds;
        MoveWindow(hwnd, (int)b.X, (int)b.Y, (int)b.Width, (int)b.Height, true);
        Activate();
        Focus();
        _windows = WindowEnum.ForPicking();
    }

    private void OnMove(object sender, MouseEventArgs e)
    {
        var cursor = OverlayHelpers.CursorPhysical();
        var pickables = _windows.Select(w => w.Pickable).ToList();
        var hit = WindowPicking.Topmost(cursor, pickables, Environment.ProcessId);

        if (hit is { } p)
        {
            _hovered = _windows.First(w => w.Pickable.Id == p.Id);
            double dip = _monitor.DpiScale;
            double x = (p.Frame.X - _monitor.Bounds.X) / dip;
            double y = (p.Frame.Y - _monitor.Bounds.Y) / dip;
            Canvas.SetLeft(Highlight, x);
            Canvas.SetTop(Highlight, y);
            Highlight.Width = p.Frame.Width / dip;
            Highlight.Height = p.Frame.Height / dip;
            Highlight.Visibility = Visibility.Visible;

            TitleText.Text = p.Title ?? string.Empty;
            Canvas.SetLeft(TitleHost, x + 8);
            Canvas.SetTop(TitleHost, y + 8);
            TitleHost.Visibility = string.IsNullOrEmpty(p.Title) ? Visibility.Collapsed : Visibility.Visible;
        }
        else
        {
            _hovered = null;
            Highlight.Visibility = Visibility.Collapsed;
            TitleHost.Visibility = Visibility.Collapsed;
        }
    }

    private void OnUp(object sender, MouseButtonEventArgs e) => Complete(_hovered?.Hwnd);

    private void OnKey(object sender, KeyEventArgs e)
    {
        if (e.Key == System.Windows.Input.Key.Escape) Complete(null);
    }

    private void Complete(IntPtr? hwnd)
    {
        if (_done) return;
        _done = true;
        Hide();
        _onPicked(hwnd);
        Close();
    }

    [DllImport("user32.dll")]
    private static extern bool MoveWindow(IntPtr hWnd, int x, int y, int width, int height, bool repaint);
}
