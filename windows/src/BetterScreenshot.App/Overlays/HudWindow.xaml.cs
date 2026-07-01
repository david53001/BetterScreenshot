using System.Windows;
using System.Windows.Threading;

namespace BetterScreenshot.App.Overlays;

/// <summary>A transient bottom-center toast (auto-dismisses after 1.5s), e.g. the Capture-Text result message.</summary>
public partial class HudWindow : Window
{
    public HudWindow(string message)
    {
        InitializeComponent();
        Message.Text = message;
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        var work = SystemParameters.WorkArea;
        Left = work.X + (work.Width - ActualWidth) / 2;
        Top = work.Bottom - ActualHeight - 80;

        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
        timer.Tick += (_, _) => { timer.Stop(); Close(); };
        timer.Start();
    }
}

/// <summary>Shows transient HUD toasts.</summary>
public static class HudController
{
    public static void Show(string message) => new HudWindow(message).Show();
}
