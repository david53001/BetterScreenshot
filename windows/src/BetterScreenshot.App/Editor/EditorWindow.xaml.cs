using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.App.Controls;
using BetterScreenshot.Capture;
using BetterScreenshot.Core;
using BetterScreenshot.Editor;
using Brushes = System.Windows.Media.Brushes;
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
using TextBlock = System.Windows.Controls.TextBlock;
using TextBox = System.Windows.Controls.TextBox;
using ToggleButton = System.Windows.Controls.Primitives.ToggleButton;

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
    private Rectangle? _marquee;
    private TextBox? _textBox;

    // Select-tool move state: the annotation being dragged, its start pointer position, and a one-time flattened
    // render of the rest of the document (base image + all *other* annotations). During a move we redraw only that
    // cached background + the single moved annotation, instead of re-flattening the whole document every frame.
    private IAnnotation? _moveOriginal;
    private PxPoint _moveDownPos;
    private BitmapSource? _moveBackground;

    // Live vector preview for shape tools (arrow/line/rect/ellipse): drawn as lightweight WPF shapes on the
    // interaction canvas while dragging, so we never rasterize a full-resolution frame per mouse-move.
    private readonly List<UIElement> _previewElements = new();

    public Action<BitmapSource>? OnCopy { get; set; }
    public Action<BitmapSource>? OnSave { get; set; }
    public Action<BitmapSource>? OnAddToStack { get; set; }
    public Action<AnnotationStyle>? StyleChanged { get; set; }

    public EditorWindow(BitmapSource image, AnnotationStyle? defaultStyle = null)
    {
        InitializeComponent();
        WindowThemer.ApplyDark(this);
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
        Loaded += (_, _) => FitToImage();

        Redraw();
    }

    private bool _fitted;

    /// <summary>
    /// Sizes the window (once, after the first layout pass) so its canvas area matches the base image's
    /// aspect ratio. This makes the image fill the canvas edge-to-edge instead of leaving wide gray
    /// pillar/letterbox gaps where drags land on nothing. Clamped to the work area and the window minimums.
    /// </summary>
    private void FitToImage()
    {
        if (_fitted || CanvasArea.ActualWidth <= 0 || CanvasArea.ActualHeight <= 0) return;
        _fitted = true;

        const double frame = 32;       // Viewbox Margin=16 on each side
        const double maxUpscale = 2.0; // don't blow a tiny capture up into a blurry wall

        double imgW = _baseImage.PixelWidth;
        double imgH = _baseImage.PixelHeight;
        if (imgW <= 0 || imgH <= 0) return;

        // Everything that isn't the canvas (title bar, window borders, tool + bottom bars) is fixed;
        // measuring it as (window − canvas) lets us resize the canvas exactly without non-client math.
        double chromeW = ActualWidth - CanvasArea.ActualWidth;
        double chromeH = ActualHeight - CanvasArea.ActualHeight;

        var work = SystemParameters.WorkArea;
        double maxDrawW = work.Width * 0.94 - chromeW - frame;
        double maxDrawH = work.Height * 0.94 - chromeH - frame;
        if (maxDrawW <= 0 || maxDrawH <= 0) return;

        double scale = Math.Min(Math.Min(maxDrawW / imgW, maxDrawH / imgH), maxUpscale);

        double winW = imgW * scale + frame + chromeW;
        double winH = imgH * scale + frame + chromeH;

        Width = Math.Max(winW, MinWidth);
        Height = Math.Max(winH, MinHeight);
        Left = work.Left + (work.Width - Width) / 2;
        Top = work.Top + (work.Height - Height) / 2;
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

    private static readonly SolidColorBrush ToolGlyphBrush = new(Color.FromRgb(0xD8, 0xD8, 0xDE));

    private readonly Dictionary<EditorTool, ToggleButton> _toolButtons = new();
    private readonly List<(RGBAColor Color, ToggleButton Button)> _colorButtons = new();
    private readonly Dictionary<double, ToggleButton> _weightButtons = new();
    private readonly Dictionary<double, ToggleButton> _sizeButtons = new();

    private void BuildToolbar()
    {
        (string Icon, string Name, EditorTool Tool)[] tools =
        {
            ("cursor", "Select", EditorTool.Select), ("arrow", "Arrow", EditorTool.Arrow),
            ("line", "Line", EditorTool.Line), ("rect", "Rectangle", EditorTool.Rectangle),
            ("rect-fill", "Filled rectangle", EditorTool.FilledRectangle),
            ("ellipse", "Ellipse", EditorTool.Ellipse), ("text", "Text", EditorTool.Text),
            ("counter", "Counter", EditorTool.Counter), ("blur", "Blur", EditorTool.Blur),
            ("pixelate", "Pixelate", EditorTool.Pixelate), ("crop", "Crop", EditorTool.Crop),
        };
        foreach (var (icon, name, tool) in tools)
        {
            var button = new ToggleButton
            {
                Content = new IconPresenter { IconKey = icon, Brush = ToolGlyphBrush, Width = 18, Height = 18 },
                Style = (Style)FindResource("Theme.ToolButton"),
                Width = 34,
                Height = 30,
                Margin = new Thickness(2, 0, 2, 0),
                ToolTip = name,
            };
            System.Windows.Automation.AutomationProperties.SetName(button, name);
            button.Click += (_, _) => SelectTool(tool);
            _toolButtons[tool] = button;
            Toolbar.Children.Add(button);
        }
        SelectTool(EditorTool.Select);
    }

    private void SelectTool(EditorTool tool)
    {
        _tool = tool;
        foreach (var (t, b) in _toolButtons)
        {
            b.IsChecked = t == tool;
            ((IconPresenter)b.Content).Brush = t == tool ? Brushes.White : ToolGlyphBrush;
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
            var c = color;
            var swatch = new ToggleButton
            {
                Style = (Style)FindResource("Theme.SwatchButton"),
                Margin = new Thickness(2, 0, 2, 0),
                Background = new SolidColorBrush(Color.FromRgb((byte)(c.R * 255), (byte)(c.G * 255), (byte)(c.B * 255))),
                ToolTip = "Color",
            };
            swatch.Click += (_, _) => SetColor(c);
            _colorButtons.Add((c, swatch));
            Inspector.Children.Add(swatch);
        }
        Inspector.Children.Add(new Separator { Width = 12, Visibility = Visibility.Hidden });
        foreach (var w in new[] { 2.0, 4.0, 7.0 })
        {
            double weight = w;
            var dot = new System.Windows.Shapes.Ellipse { Width = 3 + weight, Height = 3 + weight, Fill = Brushes.White };
            _weightButtons[weight] = InspectorToggle(dot, $"Line width {weight:0}", () => SetWeight(weight));
        }
        Inspector.Children.Add(new Separator { Width = 12, Visibility = Visibility.Hidden });
        foreach (var s in new[] { 18.0, 24.0, 36.0 })
        {
            double size = s;
            var a = new TextBlock
            {
                Text = "A", Foreground = Brushes.White, FontSize = 9 + size / 3, FontWeight = FontWeights.SemiBold,
            };
            _sizeButtons[size] = InspectorToggle(a, $"Text size {size:0}", () => SetSize(size));
        }
        RefreshInspector();
    }

    private ToggleButton InspectorToggle(UIElement content, string tip, Action onClick)
    {
        var button = new ToggleButton
        {
            Content = content,
            Style = (Style)FindResource("Theme.ToolButton"),
            Width = 30,
            Height = 28,
            Margin = new Thickness(2, 0, 2, 0),
            ToolTip = tip,
        };
        System.Windows.Automation.AutomationProperties.SetName(button, tip);
        button.Click += (_, _) => onClick();
        Inspector.Children.Add(button);
        return button;
    }

    private void RefreshInspector()
    {
        foreach (var (color, button) in _colorButtons) button.IsChecked = color == _style.StrokeColor;
        foreach (var (weight, button) in _weightButtons) button.IsChecked = Math.Abs(weight - _style.LineWidth) < 0.01;
        foreach (var (size, button) in _sizeButtons) button.IsChecked = Math.Abs(size - _style.FontSize) < 0.01;
    }

    private void SetColor(RGBAColor c) { _style = _style with { StrokeColor = c, FillColor = c.WithAlpha(0.25) }; StyleChanged?.Invoke(_style); RefreshInspector(); }
    private void SetWeight(double w) { _style = _style with { LineWidth = w }; StyleChanged?.Invoke(_style); RefreshInspector(); }
    private void SetSize(double s) { _style = _style with { FontSize = s }; StyleChanged?.Invoke(_style); RefreshInspector(); }

    /// <summary>
    /// Pointer position in base-image pixel space, clamped to the image bounds. Mouse capture keeps delivering
    /// points outside the canvas during a drag; clamping keeps drawn/placed/moved annotations inside the image
    /// (the "wall") so nothing gets dragged off the edge and lost when the document is flattened.
    /// </summary>
    private PxPoint Pos(MouseEventArgs e)
    {
        var p = e.GetPosition(InteractionLayer);
        return new PxPoint(Math.Clamp(p.X, 0, _baseImage.PixelWidth), Math.Clamp(p.Y, 0, _baseImage.PixelHeight));
    }

    private void OnDown(object sender, MouseButtonEventArgs e)
    {
        CommitText();
        var p = Pos(e);

        switch (_tool)
        {
            case EditorTool.Select:
                _selectedId = _document.TopmostHit(p);
                _moveOriginal = null;
                _moveBackground = null;
                if (_selectedId is { } hitId)
                {
                    PushUndo();
                    _moveOriginal = _document.Annotations.FirstOrDefault(a => a.Id == hitId);
                    _moveDownPos = p;
                    // Flatten everything except the annotation being moved, once, so per-frame we only draw
                    // this cached background + the single moved annotation.
                    var rest = new EditorDocument(_document.Size, _document.Annotations.Where(a => a.Id != hitId));
                    _moveBackground = DocumentRenderer.Render(rest, _baseImage);
                }
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
        if (_tool == EditorTool.Select && _moveOriginal is { } original && _moveBackground is { } background
            && e.LeftButton == MouseButtonState.Pressed)
        {
            var moved = MovedWithinBounds(original, Pos(e));
            // background is already the base image + every other annotation flattened; draw only the moved one.
            CanvasImage.Source = DocumentRenderer.Render(new EditorDocument(_document.Size), background, moved);
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
            ShowVectorPreview(start, p);
        }
    }

    /// <summary>The moved annotation, with its drag delta clamped so its bounding box stays inside the image.</summary>
    private IAnnotation MovedWithinBounds(IAnnotation original, PxPoint pointer)
    {
        double dx = pointer.X - _moveDownPos.X, dy = pointer.Y - _moveDownPos.Y;
        var b = original.BoundingBox();
        // Keep the box within [0,W] × [0,H]: shift no further left/up than its own origin, no further right/down
        // than the remaining room. (max<min only if the box is larger than the image — then pin to the edge.)
        double minDx = -b.X, maxDx = Math.Max(minDx, _baseImage.PixelWidth - b.Right);
        double minDy = -b.Y, maxDy = Math.Max(minDy, _baseImage.PixelHeight - b.Bottom);
        return original.MovedBy(Math.Clamp(dx, minDx, maxDx), Math.Clamp(dy, minDy, maxDy));
    }

    private void OnUp(object sender, MouseButtonEventArgs e)
    {
        InteractionLayer.ReleaseMouseCapture();

        // Commit a Select-tool move: write the final (clamped) position back into the document.
        if (_tool == EditorTool.Select && _selectedId is { } movedId && _moveOriginal is { } original)
        {
            _document.Replace(movedId, MovedWithinBounds(original, Pos(e)));
            _moveOriginal = null;
            _moveBackground = null;
            Redraw();
            return;
        }

        if (!_dragging || _dragStart is not { } start)
        {
            _dragging = false;
            return;
        }
        _dragging = false;
        ClearVectorPreview();
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
            Stroke = new SolidColorBrush(Color.FromRgb(0xFF, 0xFF, 0xFF)), // monochrome marquee (was blue)
            StrokeThickness = 1,
            StrokeDashArray = new DoubleCollection { 4, 3 },
            Fill = new SolidColorBrush(Color.FromArgb(0x22, 0xFF, 0xFF, 0xFF)),
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

    /// <summary>
    /// Draws the in-progress shape (arrow/line/rect/ellipse) as lightweight WPF vector shapes on the interaction
    /// canvas. Replaces the old per-frame full-resolution <see cref="RenderTargetBitmap"/> flatten — which stuttered
    /// on large captures — so the drag stays smooth regardless of image size. The shape is flattened into the
    /// document only once, on mouse-up.
    /// </summary>
    private void ShowVectorPreview(PxPoint start, PxPoint end)
    {
        ClearVectorPreview();
        foreach (var el in BuildPreviewElements(_tool, start, end, _style))
        {
            InteractionLayer.Children.Add(el);
            _previewElements.Add(el);
        }
    }

    private void ClearVectorPreview()
    {
        foreach (var el in _previewElements) InteractionLayer.Children.Remove(el);
        _previewElements.Clear();
    }

    // Coordinates are base-image pixels = InteractionLayer space (it's inside the Uniform Viewbox), so these mirror
    // what DocumentRenderer will draw on commit.
    private static IEnumerable<UIElement> BuildPreviewElements(EditorTool tool, PxPoint s, PxPoint e, AnnotationStyle style)
    {
        var stroke = PreviewBrush(style.StrokeColor);
        switch (tool)
        {
            case EditorTool.Line:
                yield return StrokeLine(s, e, stroke, style.LineWidth);
                break;
            case EditorTool.Arrow:
            {
                double headLen = Math.Max(12, style.LineWidth * 3);
                var shaftEnd = ArrowGeometry.ShaftEnd(s, e, headLen);
                yield return StrokeLine(s, shaftEnd, stroke, style.LineWidth);
                var (left, right) = ArrowGeometry.HeadWings(s, e, headLen);
                yield return new System.Windows.Shapes.Polygon
                {
                    Points = new PointCollection { new Point(e.X, e.Y), new Point(left.X, left.Y), new Point(right.X, right.Y) },
                    Fill = stroke,
                };
                break;
            }
            case EditorTool.Rectangle:
            {
                var r = SelectionMath.Normalize(s, e);
                var rect = new Rectangle { Width = r.Width, Height = r.Height, Stroke = stroke, StrokeThickness = style.LineWidth };
                Canvas.SetLeft(rect, r.X);
                Canvas.SetTop(rect, r.Y);
                yield return rect;
                break;
            }
            case EditorTool.FilledRectangle:
            {
                var r = SelectionMath.Normalize(s, e);
                var rect = new Rectangle { Width = r.Width, Height = r.Height, Fill = PreviewBrush(style.FillColor) };
                Canvas.SetLeft(rect, r.X);
                Canvas.SetTop(rect, r.Y);
                yield return rect;
                break;
            }
            case EditorTool.Ellipse:
            {
                var r = SelectionMath.Normalize(s, e);
                var el = new System.Windows.Shapes.Ellipse { Width = r.Width, Height = r.Height, Stroke = stroke, StrokeThickness = style.LineWidth };
                Canvas.SetLeft(el, r.X);
                Canvas.SetTop(el, r.Y);
                yield return el;
                break;
            }
        }
    }

    private static System.Windows.Shapes.Line StrokeLine(PxPoint a, PxPoint b, System.Windows.Media.Brush stroke, double thickness) => new()
    {
        X1 = a.X, Y1 = a.Y, X2 = b.X, Y2 = b.Y,
        Stroke = stroke, StrokeThickness = thickness,
        StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
    };

    private static SolidColorBrush PreviewBrush(RGBAColor c) =>
        new(Color.FromArgb((byte)(c.A * 255), (byte)(c.R * 255), (byte)(c.G * 255), (byte)(c.B * 255)));

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
            Background = Brushes.White,
            Foreground = Brushes.Black, // the implicit dark-theme TextBox would put light text on this white box
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
