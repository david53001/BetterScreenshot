using System.Collections.Specialized;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.App.Controls;
using Brushes = System.Windows.Media.Brushes;
using Button = System.Windows.Controls.Button;
using Color = System.Windows.Media.Color;
using Cursors = System.Windows.Input.Cursors;
using DataObject = System.Windows.DataObject;
using DragDrop = System.Windows.DragDrop;
using DragDropEffects = System.Windows.DragDropEffects;
using MouseButtonState = System.Windows.Input.MouseButtonState;
using MouseEventArgs = System.Windows.Input.MouseEventArgs;
using Path = System.Windows.Shapes.Path;
using Point = System.Windows.Point;

namespace BetterScreenshot.App.Overlays;

/// <summary>Post-capture floating card: thumbnail + action buttons; drag the thumbnail to export the file.</summary>
public partial class QuickAccessWindow : Window
{
    private static readonly SolidColorBrush GlyphBrush = new(Color.FromRgb(0x33, 0x33, 0x33));

    private readonly string? _dragFile;
    private Point _dragStart;
    private bool _done;

    public event Action<DismissReason>? Dismissed;

    public QuickAccessWindow(BitmapSource image, QuickAccessKind kind, QuickAccessActions actions, string? dragFile)
    {
        InitializeComponent();
        Thumb.Source = image;
        _dragFile = dragFile;
        Card.Background = new SolidColorBrush(kind == QuickAccessKind.Recording
            ? Color.FromRgb(0xE8, 0xF0, 0xFE)
            : Color.FromRgb(0xFA, 0xFA, 0xFC));

        if (kind == QuickAccessKind.Screenshot)
        {
            ButtonRow.Children.Add(MakeButton("copy", "Copy", actions.OnCopy));
            ButtonRow.Children.Add(MakeButton("edit", "Edit", () => { actions.OnEdit(); Dismiss(DismissReason.ActionTaken); }));
            ButtonRow.Children.Add(MakeButton("pin", "Pin to screen", () => { actions.OnPin(); Dismiss(DismissReason.ActionTaken); }));
            ButtonRow.Children.Add(MakeButton("save", "Save", () => { actions.OnSave(); Dismiss(DismissReason.ActionTaken); }));
            ButtonRow.Children.Add(MakeButton("close", "Close", () => Dismiss(DismissReason.Closed)));
        }
        else
        {
            ButtonRow.Children.Add(MakeButton("copy", "Copy file", actions.OnCopy));
            ButtonRow.Children.Add(MakeButton("play", "Open", () => { actions.OnOpen(); Dismiss(DismissReason.ActionTaken); }));
            ButtonRow.Children.Add(MakeButton("folder", "Show in folder", () => { actions.OnReveal(); Dismiss(DismissReason.ActionTaken); }));
            ButtonRow.Children.Add(MakeButton("close", "Close", () => Dismiss(DismissReason.Closed)));
        }

        Thumb.MouseLeftButtonDown += (_, e) => _dragStart = e.GetPosition(this);
        Thumb.MouseMove += Thumb_MouseMove;
    }

    public void MoveTo(double left, double top)
    {
        Left = left;
        Top = top;
    }

    public void ForceDismiss(DismissReason reason) => Dismiss(reason);

    private void Thumb_MouseMove(object sender, MouseEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed || _dragFile is null) return;
        var p = e.GetPosition(this);
        if (Math.Abs(p.X - _dragStart.X) < 4 && Math.Abs(p.Y - _dragStart.Y) < 4) return;

        var data = new DataObject();
        data.SetFileDropList(new StringCollection { _dragFile });
        DragDrop.DoDragDrop(Thumb, data, DragDropEffects.Copy);
    }

    private void Dismiss(DismissReason reason)
    {
        if (_done) return;
        _done = true;
        Dismissed?.Invoke(reason);
        Close();
    }

    private static Button MakeButton(string iconKey, string tip, Action onClick)
    {
        var button = new Button
        {
            Content = new IconPresenter { IconKey = iconKey, Brush = GlyphBrush, Width = 17, Height = 17 },
            Width = 30,
            Height = 28,
            Margin = new Thickness(3, 0, 3, 0),
            ToolTip = tip,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Cursor = Cursors.Hand,
        };
        button.Click += (_, _) => onClick();
        return button;
    }
}
