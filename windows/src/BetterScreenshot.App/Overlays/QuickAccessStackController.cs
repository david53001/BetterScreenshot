using System.Windows;
using System.Windows.Media.Imaging;
using BetterScreenshot.Core;

namespace BetterScreenshot.App.Overlays;

/// <summary>
/// Manages up to 3 stacked Quick Access cards at a screen corner. A new capture inserts at the front; the
/// oldest is evicted when full; dismissing a card restacks the rest. Cards now vary in height (each is sized
/// to its image's aspect ratio), so positions are computed cumulatively from the corner.
/// </summary>
public sealed class QuickAccessStackController
{
    private const int MaxCount = 3;
    private const double Margin = 24;
    private const double Spacing = 12;

    private readonly List<QuickAccessWindow> _cards = new(); // index 0 = newest

    public void Present(BitmapSource image, QuickAccessKind kind, QuickAccessActions actions, Corner corner,
        string? dragFile, int autoDismissSeconds = 0, Action<DismissReason>? onDismiss = null)
    {
        if (_cards.Count >= MaxCount)
        {
            var oldest = _cards[^1];
            _cards.RemoveAt(_cards.Count - 1);
            oldest.ForceDismiss(DismissReason.Evicted);
        }

        var card = new QuickAccessWindow(image, kind, actions, dragFile, autoDismissSeconds);
        card.Dismissed += reason =>
        {
            _cards.Remove(card);
            Restack(corner);
            onDismiss?.Invoke(reason);
        };
        _cards.Insert(0, card);
        Restack(corner);
        card.Show();
    }

    // Stack cards cumulatively from the chosen corner using each card's actual size (heights differ per image).
    // Bottom corners stack upward, top corners stack downward; index 0 (newest) sits closest to the corner.
    private void Restack(Corner corner)
    {
        var work = SystemParameters.WorkArea;
        bool isRight = corner is Corner.TopRight or Corner.BottomRight;
        bool isBottom = corner is Corner.BottomLeft or Corner.BottomRight;

        double cursor = isBottom ? work.Bottom - Margin : work.Top + Margin;
        foreach (var card in _cards)
        {
            double x = isRight ? work.Right - card.Width - Margin : work.Left + Margin;
            double y = isBottom ? cursor - card.Height : cursor;
            card.MoveTo(x, y);
            cursor = isBottom ? y - Spacing : y + card.Height + Spacing;
        }
    }
}
