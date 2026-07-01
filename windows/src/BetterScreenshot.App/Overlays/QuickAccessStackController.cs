using System.Windows;
using System.Windows.Media.Imaging;
using BetterScreenshot.Capture;
using BetterScreenshot.Core;

namespace BetterScreenshot.App.Overlays;

/// <summary>
/// Manages up to 3 stacked Quick Access cards at a screen corner (positions via the pure OverlayPositioner). A new
/// capture inserts at the front; the oldest is evicted when full; dismissing a card restacks the rest.
/// </summary>
public sealed class QuickAccessStackController
{
    private const int MaxCount = 3;
    private const double CardWidth = 220;
    private const double CardHeight = 168;
    private const double Margin = 24;

    private readonly List<QuickAccessWindow> _cards = new(); // index 0 = newest

    public void Present(BitmapSource image, QuickAccessKind kind, QuickAccessActions actions, Corner corner, string? dragFile)
    {
        if (_cards.Count >= MaxCount)
        {
            var oldest = _cards[^1];
            _cards.RemoveAt(_cards.Count - 1);
            oldest.ForceDismiss(DismissReason.Evicted);
        }

        var card = new QuickAccessWindow(image, kind, actions, dragFile);
        card.Dismissed += _ =>
        {
            _cards.Remove(card);
            Restack(corner);
        };
        _cards.Insert(0, card);
        Restack(corner);
        card.Show();
    }

    private void Restack(Corner corner)
    {
        var work = SystemParameters.WorkArea;
        var frame = new PxRect(work.X, work.Y, work.Width, work.Height);
        for (int i = 0; i < _cards.Count; i++)
        {
            var origin = OverlayPositioner.StackedOrigin(corner, new PxSize(CardWidth, CardHeight), frame, Margin, i);
            _cards[i].MoveTo(origin.X, origin.Y);
        }
    }
}
