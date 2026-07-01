using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.Capture;
using BetterScreenshot.Core;
using BetterScreenshot.Editor;
using Button = System.Windows.Controls.Button;
using Canvas = System.Windows.Controls.Canvas;
using Color = System.Windows.Media.Color;
using Cursors = System.Windows.Input.Cursors;
using Key = System.Windows.Input.Key;
using Keyboard = System.Windows.Input.Keyboard;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using ModifierKeys = System.Windows.Input.ModifierKeys;
using MouseButtonEventArgs = System.Windows.Input.MouseButtonEventArgs;
using MouseButtonState = System.Windows.Input.MouseButtonState;
using MouseEventArgs = System.Windows.Input.MouseEventArgs;
using Point = System.Windows.Point;
using Rectangle = System.Windows.Shapes.Rectangle;
using Separator = System.Windows.Controls.Separator;
using TextBox = System.Windows.Controls.TextBox;

namespace BetterScreenshot.App.Editor;

/// <summary>
/// Annotation editor with drawing tools, a color/size inspector, snapshot undo/redo (Ctrl+Z / Ctrl+Shift+Z /
/// Ctrl+Y), and sticky style (the last-used style is reported via <see cref="StyleChanged"/> for persistence).
/// </summary>
public partial class EditorWindow : Window
{
    private sealed record EditorState(EditorDocument Document, BitmapSource BaseImage);

    private BitmapSource _baseImage;
    private EditorDocument _document;
    private AnnotationStyle _style;
    private EditorTool _tool = EditorTool.Select;
    private readonly UndoHistory<EditorState> _history = new();

    private PxPoint? _dragStart;
    private bool _dragging;
    private Guid? _selectedId;
    private Point _lastMove;
    private Rectangle? _marquee;
    private TextBox? _textBox;

    public Action<BitmapSource>? OnCopy { get; set; }
    public Action<BitmapSource>? OnSave { get; set; }
    public Action<BitmapSource>? OnAddToStack { get; set; }
    public Action<AnnotationStyle>? StyleChanged { get; set; }

    public EditorWindow(BitmapSource image, AnnotationStyle? defaultStyle = null)
    {
        InitializeComponent();
        _baseImage = image;
        _style = defaultStyle ?? AnnotationStyle.Default;
        _document = new EditorDocument(new PxSize(image.PixelWidth, image.PixelHeight));
        ResizeStage();
        BuildToolbar();
        BuildInspector();

        InteractionLayer.MouseLeftButtonDown += OnDown;
        InteractionLayer.MouseMove += OnMove;
        InteractionLayer.MouseLeftButtonUp += OnUp;
        KeyDown += OnKeyDown;

        Redraw();
    }

    private EditorState Snapshot() => new(new EditorDocument(_document.Size, _document.Annotations), _baseImage);
    private void PushUndo() => _history.Push(Snapshot());

    private void ResizeStage()
    {
        Stage.Width = _baseImage.PixelWidth;
        Stage.Height = _baseImage.PixelHeight;
        InteractionLayer.Width = _baseImage.PixelWidth;
        InteractionLayer.Height = _baseImage.PixelHeight;
    }

    private void BuildToolbar()
    {
        (string Label, EditorTool Tool)[] tools =
        {
            ("Select", EditorTool.Select), ("Arrow", EditorTool.Arrow), ("Line", EditorTool.Line),
            ("Rect", EditorTool.Rectangle), ("Fill", EditorTool.FilledRectangle), ("Ellipse", EditorTool.Ellipse),
            ("Text", EditorTool.Text), ("Counter", EditorTool.Counter), ("Blur", EditorTool.Blur),
            ("Pixel", EditorTool.Pixelate), ("Crop", EditorTool.Crop),
        };
        foreach (var (label, tool) in tools)
        {
            var button = new Button { Content = label, Padding = new Thickness(9, 4, 9, 4), Margin = new Thickness(2, 0, 2, 0), Tag = tool };
            button.Click += (_, _) => _tool = (EditorTool)button.Tag;
            Toolbar.Children.Add(button);
        }
    }

    private void BuildInspector()
    {
        RGBAColor[] presets =
        {
            new(1, 0.27, 0.23, 1), new(1, 0.62, 0.04, 1), new(1, 0.84, 0.04, 1), new(0.19, 0.82, 0.35, 1),
            new(0.04, 0.52, 1, 1), new(0.75, 0.35, 0.95, 1), new(1, 1, 1, 1), new(0, 0, 0, 1),
        };
        foreach (var color in presets)
        {
            var swatch = new Button
            {
                Width = 22,
                Height = 22,
                Margin = new Thickness(2, 0, 2, 0),
                Background = new SolidColorBrush(Color.FromRgb((byte)(color.R * 255), (byte)(color.G * 255), (byte)(color.B * 255))),
            };
            var c = color;
            swatch.Click += (_, _) => SetColor(c);
            Inspector.Children.Add(swatch);
        }
        Inspector.Children.Add(new Separator { Width = 10, Visibility = Visibility.Hidden });
        foreach (var w in new[] { 2.0, 4.0, 7.0 }) AddInspectorButton(w.ToString("0"), () => SetWeight(w));
        Inspector.Children.Add(new Separator { Width = 10, Visibility = Visibility.Hidden });
        foreach (var s in new[] { 18.0, 24.0, 36.0 }) AddInspectorButton(s.ToString("0"), () => SetSize(s));
    }

    private void AddInspectorButton(string label, Action onClick)
    {
        var button = new Button { Content = label, Padding = new Thickness(8, 3, 8, 3), Margin = new Thickness(2, 0, 2, 0) };
        button.Click += (_, _) => onClick();
        Inspector.Children.Add(button);
    }

    private void SetColor(RGBAColor c) { _style = _style with { StrokeColor = c, FillColor = c.WithAlpha(0.25) }; StyleChanged?.Invoke(_style); }
    private void SetWeight(double w) { _style = _style with { LineWidth = w }; StyleChanged?.Invoke(_style); }
    private void SetSize(double s) { _style = _style with { FontSize = s }; StyleChanged?.Invoke(_style); }

    private PxPoint Pos(MouseEventArgs e)
    {
        var p = e.GetPosition(InteractionLayer);
        return new PxPoint(p.X, p.Y);
    }

    private void OnDown(object sender, MouseButtonEventArgs e)
    {
        CommitText();
        var p = Pos(e);

        switch (_tool)
        {
            case EditorTool.Select:
                _selectedId = _document.TopmostHit(p);
                if (_selectedId != null) PushUndo();
                _lastMove = e.GetPosition(InteractionLayer);
                InteractionLayer.CaptureMouse();
                return;
            case EditorTool.Counter:
                PushUndo();
                _document.Add(CounterAnnotation.Centered(p, _document.NextCounterNumber(), _style));
                Redraw();
                return;
            case EditorTool.Text:
                PlaceTextBox(p);
                return;
            default:
                _dragStart = p;
                _dragging = true;
                if (_tool is EditorTool.Blur or EditorTool.Pixelate or EditorTool.Crop) BeginMarquee(p);
                InteractionLayer.CaptureMouse();
                return;
        }
    }

    private void OnMove(object sender, MouseEventArgs e)
    {
        if (_tool == EditorTool.Select && _selectedId is { } id && e.LeftButton == MouseButtonState.Pressed)
        {
            var now = e.GetPosition(InteractionLayer);
            _document.Move(id, now.X - _lastMove.X, now.Y - _lastMove.Y);
            _lastMove = now;
            Redraw();
            return;
        }

        if (!_dragging || _dragStart is not { } start) return;
        var p = Pos(e);

        if (_marquee != null)
        {
            var rect = SelectionMath.Normalize(start, p);
            Canvas.SetLeft(_marquee, rect.X);
            Canvas.SetTop(_marquee, rect.Y);
            _marquee.Width = rect.Width;
            _marquee.Height = rect.Height;
        }
        else
        {
            var preview = AnnotationFactory.CreateDrag(_tool, start, p, _style);
            CanvasImage.Source = DocumentRenderer.Render(_document, _baseImage, preview);
        }
    }

    private void OnUp(object sender, MouseButtonEventArgs e)
    {
        InteractionLayer.ReleaseMouseCapture();

        if (!_dragging || _dragStart is not { } start)
        {
            _dragging = false;
            return;
        }
        _dragging = false;
        var end = Pos(e);
        var frame = SelectionMath.Normalize(start, end);

        switch (_tool)
        {
            case EditorTool.Crop:
                EndMarquee();
                if (frame.Width >= 4 && frame.Height >= 4) { PushUndo(); ApplyCrop(frame); }
                break;
            case EditorTool.Blur:
            case EditorTool.Pixelate:
                EndMarquee();
                if (frame.Width >= 2 && frame.Height >= 2) { PushUndo(); ApplyRedaction(frame, _tool == EditorTool.Blur); }
                break;
            default:
                var annotation = AnnotationFactory.CreateDrag(_tool, start, end, _style);
                if (annotation != null) { PushUndo(); _document.Add(annotation); }
                break;
        }
        _dragStart = null;
        Redraw();
    }

    private void OnKeyDown(object sender, KeyEventArgs e)
    {
        bool ctrl = (Keyboard.Modifiers & ModifierKeys.Control) != 0;
        bool shift = (Keyboard.Modifiers & ModifierKeys.Shift) != 0;
        if (ctrl && e.Key == Key.Z && !shift) { Undo(); e.Handled = true; return; }
        if (ctrl && (e.Key == Key.Y || (e.Key == Key.Z && shift))) { Redo(); e.Handled = true; return; }

        if (_textBox != null) return; // let the text box handle keys
        if (_selectedId is not { } id) return;

        switch (e.Key)
        {
            case Key.Delete:
            case Key.Back:
                PushUndo();
                _document.Remove(id);
                _selectedId = null;
                Redraw();
                break;
            case Key.OemOpenBrackets:
                PushUndo();
                _document.SendToBack(id);
                Redraw();
                break;
            case Key.OemCloseBrackets:
                PushUndo();
                _document.BringToFront(id);
                Redraw();
                break;
        }
    }

    private void Undo()
    {
        if (!_history.TryUndo(Snapshot(), out var prev)) return;
        _document = prev.Document;
        _baseImage = prev.BaseImage;
        _selectedId = null;
        ResizeStage();
        Redraw();
    }

    private void Redo()
    {
        if (!_history.TryRedo(Snapshot(), out var next)) return;
        _document = next.Document;
        _baseImage = next.BaseImage;
        _selectedId = null;
        ResizeStage();
        Redraw();
    }

    private void BeginMarquee(PxPoint start)
    {
        _marquee = new Rectangle
        {
            Stroke = new SolidColorBrush(Color.FromRgb(0x0A, 0x84, 0xFF)),
            StrokeThickness = 1,
            StrokeDashArray = new DoubleCollection { 4, 3 },
            Fill = new SolidColorBrush(Color.FromArgb(0x22, 0x0A, 0x84, 0xFF)),
        };
        Canvas.SetLeft(_marquee, start.X);
        Canvas.SetTop(_marquee, start.Y);
        InteractionLayer.Children.Add(_marquee);
    }

    private void EndMarquee()
    {
        if (_marquee != null) InteractionLayer.Children.Remove(_marquee);
        _marquee = null;
    }

    private void ApplyRedaction(PxRect frame, bool blur)
    {
        if (ClampToBase(frame) is not { } r) return;
        var cropped = new CroppedBitmap(_baseImage, new Int32Rect(r.X, r.Y, r.W, r.H));
        var argb = ImageConvert.ToArgbImage(cropped);
        var patch = blur
            ? Redactor.Blur(argb, new PxRect(0, 0, argb.Width, argb.Height))
            : Redactor.Pixelate(argb, new PxRect(0, 0, argb.Width, argb.Height));
        if (patch is null) return;
        var pxFrame = new PxRect(r.X, r.Y, r.W, r.H);
        _document.Add(blur
            ? new BlurAnnotation(Guid.NewGuid(), _style, pxFrame, patch)
            : new PixelateAnnotation(Guid.NewGuid(), _style, pxFrame, patch));
    }

    private void ApplyCrop(PxRect frame)
    {
        if (ClampToBase(frame) is not { } r) return;
        _document = _document.Cropped(new PxRect(r.X, r.Y, r.W, r.H));
        _baseImage = new CroppedBitmap(_baseImage, new Int32Rect(r.X, r.Y, r.W, r.H));
        ResizeStage();
    }

    private (int X, int Y, int W, int H)? ClampToBase(PxRect frame)
    {
        int x = Math.Clamp((int)Math.Round(frame.X), 0, _baseImage.PixelWidth);
        int y = Math.Clamp((int)Math.Round(frame.Y), 0, _baseImage.PixelHeight);
        int w = Math.Min((int)Math.Round(frame.Width), _baseImage.PixelWidth - x);
        int h = Math.Min((int)Math.Round(frame.Height), _baseImage.PixelHeight - y);
        return w >= 1 && h >= 1 ? (x, y, w, h) : null;
    }

    private void PlaceTextBox(PxPoint p)
    {
        _textBox = new TextBox
        {
            MinWidth = 80,
            FontSize = _style.FontSize,
            Background = System.Windows.Media.Brushes.White,
            Tag = p,
        };
        Canvas.SetLeft(_textBox, p.X);
        Canvas.SetTop(_textBox, p.Y);
        InteractionLayer.Children.Add(_textBox);
        _textBox.Focus();
        _textBox.LostKeyboardFocus += (_, _) => CommitText();
        _textBox.KeyDown += (_, ke) => { if (ke.Key == Key.Enter) CommitText(); };
    }

    private void CommitText()
    {
        if (_textBox is null) return;
        var box = _textBox;
        _textBox = null;
        var origin = (PxPoint)box.Tag;
        string text = box.Text;
        InteractionLayer.Children.Remove(box);
        if (!string.IsNullOrWhiteSpace(text))
        {
            PushUndo();
            _document.Add(new TextAnnotation(Guid.NewGuid(), _style, text, origin));
            Redraw();
        }
    }

    private void Redraw() => CanvasImage.Source = DocumentRenderer.Render(_document, _baseImage);
    private BitmapSource Export() => DocumentRenderer.Render(_document, _baseImage);

    private void Done_Click(object sender, RoutedEventArgs e) => Close();
    private void Copy_Click(object sender, RoutedEventArgs e) => OnCopy?.Invoke(Export());
    private void Save_Click(object sender, RoutedEventArgs e) { OnSave?.Invoke(Export()); Close(); }
    private void Stack_Click(object sender, RoutedEventArgs e) { OnAddToStack?.Invoke(Export()); Close(); }
}
