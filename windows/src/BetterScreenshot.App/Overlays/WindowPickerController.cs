using System.Windows.Threading;

namespace BetterScreenshot.App.Overlays;

/// <summary>Shows the interactive window picker on the monitor under the cursor and returns the chosen HWND.</summary>
public sealed class WindowPickerController
{
    public void Present(Action<IntPtr?> onPicked)
    {
        var monitor = OverlayHelpers.MonitorUnderCursor();
        var window = new WindowPickerWindow(monitor, hwnd =>
            System.Windows.Application.Current.Dispatcher.BeginInvoke(
                DispatcherPriority.Background, new Action(() => onPicked(hwnd))));
        window.Show();
    }
}
