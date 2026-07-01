using System.Windows;
using System.Windows.Media.Imaging;
using BetterScreenshot.Capture;
using BetterScreenshot.Core;
using BetterScreenshot.Platform;

namespace BetterScreenshot.App.Overlays;

/// <summary>Creates and tracks pinned image panels (multi-pin), sized via the tested <see cref="PinGeometry"/>.</summary>
public sealed class PinPanelController
{
    private readonly List<PinWindow> _pins = new();

    public void Pin(BitmapSource image, PinStyle style, PinActions actions)
    {
        double dpi = Screens.Primary().DpiScale;
        var work = SystemParameters.WorkArea;
        var visible = new PxRect(work.X, work.Y, work.Width, work.Height);

        var frame = PinGeometry.InitialFrame(new PxSize(image.PixelWidth, image.PixelHeight), dpi, visible);
        var naturalSize = new PxSize(image.PixelWidth / dpi, image.PixelHeight / dpi);

        var window = new PinWindow(image, style, actions, naturalSize)
        {
            Left = frame.X,
            Top = frame.Y,
            Width = frame.Width,
            Height = frame.Height,
        };
        window.Closed += (_, _) => _pins.Remove(window);
        _pins.Add(window);
        window.Show();
    }
}
