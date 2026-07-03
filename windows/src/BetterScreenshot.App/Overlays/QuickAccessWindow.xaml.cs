using System.Collections.Specialized;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.App.Controls;
using Brush = System.Windows.Media.Brush;
using Button = System.Windows.Controls.Button;
using DataObject = System.Windows.DataObject;
using DragDrop = System.Windows.DragDrop;
using DragDropEffects = System.Windows.DragDropEffects;
using MouseButtonState = System.Windows.Input.MouseButtonState;
using MouseEventArgs = System.Windows.Input.MouseEventArgs;
using Point = System.Windows.Point;

namespace BetterScreenshot.App.Overlays;

/// <summary>
/// Post-capture floating card. The captured image fills the whole rounded block edge-to-edge; the action
/// buttons overlay the bottom of the image on an auto-contrasting scrim (see <see cref="ContrastPalette"/>).
/// Drag the card to export the file.
/// </summary>
public partial class QuickAccessWindow : Window
{
    private const double ContentWidth = 210;      // image (card) width in DIPs; height derives from the image aspect
    private const double MinContentHeight = 150;  // widest card ~= 210/150 = 1.40:1 — a mild rectangle, not a 16:9 sliver,
                                                  // so the button row hugs the width instead of floating in bare image
    private const double MaxContentHeight = 280;
    private const double CornerRadiusPx = 14;     // must match the Hairline CornerRadius in the XAML
    private const double ShadowMargin = 6;        // must match the shadow-host Border Margin in the XAML

    private readonly string? _dragFile;
    private Point _dragStart;
    private bool _done;

    public event Action<DismissReason>? Dismissed;

    public QuickAccessWindow(BitmapSource image, QuickAccessKind kind, QuickAccessActions actions, string? dragFile)
    {
        InitializeComponent();
        Thumb.Source = image;
        _dragFile = dragFile;

        // Size the card to the image so it fills the whole rounded block with no letterbox. Extreme aspect
        // ratios clamp; UniformToFill then crops the long side to keep the image full-bleed.
        double aspect = image.PixelHeight > 0 ? (double)image.PixelWidth / image.PixelHeight : 16.0 / 9.0;
        double contentHeight = Math.Clamp(ContentWidth / aspect, MinContentHeight, MaxContentHeight);
        Width = ContentWidth + 2 * ShadowMargin;
        Height = contentHeight + 2 * ShadowMargin;

        Scrim.Height = Math.Min(64, contentHeight * 0.42);
        Root.Clip = RoundedClip(ContentWidth, contentHeight);
        Root.SizeChanged += (_, _) => Root.Clip = RoundedClip(Root.ActualWidth, Root.ActualHeight);

        // Auto-contrast the overlaid controls to whatever the image shows behind the toolbar.
        var palette = ContrastPalette.ForImageBottom(image);
        Scrim.Fill = palette.Scrim;
        Resources["QA.HoverBrush"] = palette.Hover;
        Resources["QA.PressedBrush"] = palette.Pressed;

        if (kind == QuickAccessKind.Screenshot)
        {
            ButtonRow.Children.Add(MakeButton("copy", "Copy", palette.Glyph, actions.OnCopy));
            ButtonRow.Children.Add(MakeButton("edit", "Edit", palette.Glyph, () => { actions.OnEdit(); Dismiss(DismissReason.ActionTaken); }));
            ButtonRow.Children.Add(MakeButton("pin", "Pin to screen", palette.Glyph, () => { actions.OnPin(); Dismiss(DismissReason.ActionTaken); }));
            ButtonRow.Children.Add(MakeButton("save", "Save", palette.Glyph, () => { actions.OnSave(); Dismiss(DismissReason.ActionTaken); }));
            ButtonRow.Children.Add(MakeButton("close", "Close", palette.Glyph, () => Dismiss(DismissReason.Closed)));
        }
        else
        {
            ButtonRow.Children.Add(MakeButton("copy", "Copy file", palette.Glyph, actions.OnCopy));
            ButtonRow.Children.Add(MakeButton("play", "Open", palette.Glyph, () => { actions.OnOpen(); Dismiss(DismissReason.ActionTaken); }));
            ButtonRow.Children.Add(MakeButton("folder", "Show in folder", palette.Glyph, () => { actions.OnReveal(); Dismiss(DismissReason.ActionTaken); }));
            ButtonRow.Children.Add(MakeButton("close", "Close", palette.Glyph, () => Dismiss(DismissReason.Closed)));
        }

        DragSurface.MouseLeftButtonDown += (_, e) => _dragStart = e.GetPosition(this);
        DragSurface.MouseMove += DragSurface_MouseMove;
    }

    public void MoveTo(double left, double top)
    {
        Left = left;
        Top = top;
    }

    public void ForceDismiss(DismissReason reason) => Dismiss(reason);

    private static RectangleGeometry RoundedClip(double w, double h) =>
        new(new Rect(0, 0, w, h), CornerRadiusPx, CornerRadiusPx);

    private void DragSurface_MouseMove(object sender, MouseEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed || _dragFile is null) return;
        var p = e.GetPosition(this);
        if (Math.Abs(p.X - _dragStart.X) < 4 && Math.Abs(p.Y - _dragStart.Y) < 4) return;

        var data = new DataObject();
        data.SetFileDropList(new StringCollection { _dragFile });
        var result = DragDrop.DoDragDrop(DragSurface, data, DragDropEffects.Copy);
        if (result != DragDropEffects.None) Dismiss(DismissReason.ActionTaken); // Esc-cancel keeps the card
    }

    private void Dismiss(DismissReason reason)
    {
        if (_done) return;
        _done = true;
        Dismissed?.Invoke(reason);
        Close();
    }

    private Button MakeButton(string iconKey, string tip, Brush glyph, Action onClick)
    {
        var button = new Button
        {
            Content = new IconPresenter { IconKey = iconKey, Brush = glyph, Width = 17, Height = 17 },
            Width = 32,
            Height = 30,
            Margin = new Thickness(2, 0, 2, 0),
            ToolTip = tip,
            Style = (Style)FindResource("QA.IconButton"),
        };
        System.Windows.Automation.AutomationProperties.SetName(button, tip); // accessible name for an icon-only button
        button.Click += (_, _) => onClick();
        return button;
    }
}
