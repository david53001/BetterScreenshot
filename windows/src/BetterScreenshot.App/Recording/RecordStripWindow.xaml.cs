using System.Windows;
using System.Windows.Media;
using BetterScreenshot.Platform;
using BetterScreenshot.Recording;
using Border = System.Windows.Controls.Border;
using Button = System.Windows.Controls.Button;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using Cursors = System.Windows.Input.Cursors;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using Orientation = System.Windows.Controls.Orientation;
using Path = System.Windows.Shapes.Path;
using StackPanel = System.Windows.Controls.StackPanel;
using VerticalAlignment = System.Windows.VerticalAlignment;

namespace BetterScreenshot.App.Recording;

/// <summary>
/// The pre-record control strip (mac <c>RecordStripController</c>): a floating bottom-center panel with target
/// buttons (Full Screen / Window / Area), an MP4/GIF format toggle, and system-audio/mic/camera toggles that
/// persist to <see cref="SettingsStore"/> live. The <see cref="RecordingCoordinator"/> shows it on arm, hides it
/// when a target is chosen or on cancel. Positioned on the primary work area (cursor-monitor placement is a
/// hardening refinement); all glyphs are hand-authored vector geometry.
/// </summary>
public partial class RecordStripWindow : Window
{
    private static readonly SolidColorBrush AccentBrush = new(Color.FromRgb(0x2F, 0x6F, 0xEB));
    private static readonly SolidColorBrush GlyphOff = new(Color.FromRgb(0x33, 0x33, 0x33));
    private static readonly SolidColorBrush GlyphOn = new(Color.FromRgb(0xFF, 0xFF, 0xFF));

    private readonly SettingsStore _settings;

    public Action? OnFullScreen { get; set; }
    public Action? OnArea { get; set; }
    public Action? OnWindow { get; set; }
    public Action? OnCancel { get; set; }

    public RecordStripWindow(SettingsStore settings)
    {
        InitializeComponent();
        _settings = settings;
        BuildControls();
        Loaded += (_, _) => Reposition();
    }

    private void BuildControls()
    {
        ControlRow.Children.Add(TextButton("Record Full Screen", () => OnFullScreen?.Invoke()));
        ControlRow.Children.Add(TextButton("Record Window…", () => OnWindow?.Invoke()));
        ControlRow.Children.Add(TextButton("Record Area…", () => OnArea?.Invoke()));
        ControlRow.Children.Add(Separator());
        ControlRow.Children.Add(BuildFormatSegment());
        ControlRow.Children.Add(IconToggle(Glyphs.Speaker, "Record system audio", _settings.Recording.SystemAudio,
            on => Persist(_settings.Recording with { SystemAudio = on })));
        ControlRow.Children.Add(IconToggle(Glyphs.Mic, "Record microphone", _settings.Recording.Microphone,
            on => Persist(_settings.Recording with { Microphone = on })));
        ControlRow.Children.Add(IconToggle(Glyphs.Video, "Show camera bubble", _settings.Recording.Camera,
            on => Persist(_settings.Recording with { Camera = on })));
        ControlRow.Children.Add(Separator());
        ControlRow.Children.Add(IconButton(Glyphs.Close, "Cancel", () => OnCancel?.Invoke()));
    }

    private void Persist(RecordingConfig config)
    {
        _settings.Recording = config;
        _settings.Save();
    }

    private UIElement BuildFormatSegment()
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(4, 0, 4, 0) };
        Button mp4 = null!, gif = null!;
        void Refresh()
        {
            bool isMp4 = _settings.Recording.Format == RecordingFormat.Mp4;
            StyleSegment(mp4, isMp4);
            StyleSegment(gif, !isMp4);
        }
        mp4 = SegmentButton("MP4", () => { Persist(_settings.Recording with { Format = RecordingFormat.Mp4 }); Refresh(); });
        gif = SegmentButton("GIF", () => { Persist(_settings.Recording with { Format = RecordingFormat.Gif }); Refresh(); });
        panel.Children.Add(mp4);
        panel.Children.Add(gif);
        Refresh();
        return panel;
    }

    private void Reposition()
    {
        var work = SystemParameters.WorkArea; // logical DIPs on the primary monitor
        Left = work.Left + (work.Width - ActualWidth) / 2;
        Top = work.Bottom - ActualHeight - 60;
    }

    private static Button TextButton(string text, Action onClick)
    {
        var b = new Button
        {
            Content = text,
            Padding = new Thickness(10, 5, 10, 5),
            Margin = new Thickness(3, 0, 3, 0),
            FontSize = 12,
            Cursor = Cursors.Hand,
        };
        b.Click += (_, _) => onClick();
        return b;
    }

    private static Button SegmentButton(string text, Action onClick)
    {
        var b = new Button { Content = text, Width = 46, Height = 28, FontSize = 12, Cursor = Cursors.Hand };
        b.Click += (_, _) => onClick();
        return b;
    }

    private static void StyleSegment(Button b, bool selected)
    {
        b.Background = selected ? AccentBrush : Brushes.Transparent;
        b.Foreground = selected ? GlyphOn : GlyphOff;
    }

    private static Button IconToggle(string glyph, string tip, bool initial, Action<bool> onChanged)
    {
        bool state = initial;
        var path = GlyphPath(glyph);
        var b = new Button
        {
            Content = path,
            Width = 34,
            Height = 30,
            Margin = new Thickness(2, 0, 2, 0),
            ToolTip = tip,
            Cursor = Cursors.Hand,
            BorderThickness = new Thickness(0),
        };
        void Apply()
        {
            b.Background = state ? AccentBrush : Brushes.Transparent;
            path.Stroke = state ? GlyphOn : GlyphOff;
        }
        Apply();
        b.Click += (_, _) => { state = !state; Apply(); onChanged(state); };
        return b;
    }

    private static Button IconButton(string glyph, string tip, Action onClick)
    {
        var b = new Button
        {
            Content = GlyphPath(glyph),
            Width = 30,
            Height = 30,
            Margin = new Thickness(2, 0, 0, 0),
            ToolTip = tip,
            Cursor = Cursors.Hand,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
        };
        b.Click += (_, _) => onClick();
        return b;
    }

    private static Path GlyphPath(string data) => new()
    {
        Data = Geometry.Parse(data),
        Stretch = Stretch.Uniform,
        Width = 18,
        Height = 18,
        Stroke = GlyphOff,
        StrokeThickness = 1.6,
        StrokeStartLineCap = PenLineCap.Round,
        StrokeEndLineCap = PenLineCap.Round,
        StrokeLineJoin = PenLineJoin.Round,
    };

    private static UIElement Separator() => new Border
    {
        Width = 1,
        Height = 22,
        Background = new SolidColorBrush(Color.FromRgb(0xDD, 0xDD, 0xDD)),
        Margin = new Thickness(6, 0, 6, 0),
        VerticalAlignment = VerticalAlignment.Center,
    };

    /// <summary>Hand-authored 24×24 stroke glyphs for the strip toggles (approximate the mac SF Symbols).</summary>
    private static class Glyphs
    {
        // mic: capsule + arc + stand + base.
        public const string Mic =
            "M12,4 C10.3,4 9,5.3 9,7 L9,11 C9,12.7 10.3,14 12,14 C13.7,14 15,12.7 15,11 L15,7 C15,5.3 13.7,4 12,4 Z " +
            "M6.5,11 C6.5,14 9,16.5 12,16.5 C15,16.5 17.5,14 17.5,11 M12,16.5 L12,20 M9,20 L15,20";
        // speaker.wave.2: speaker cone + two waves.
        public const string Speaker =
            "M4,9 L7,9 L11,5.5 L11,18.5 L7,15 L4,15 Z M14.5,9.5 C16,11 16,13 14.5,14.5 M16.5,7.5 C19,10 19,14 16.5,16.5";
        // video: camcorder body + lens.
        public const string Video = "M4,7 L13,7 L13,17 L4,17 Z M13,10.5 L18.5,7.5 L18.5,16.5 L13,13.5 Z";
        // xmark.
        public const string Close = "M7,7 L17,17 M17,7 L7,17";
    }
}
