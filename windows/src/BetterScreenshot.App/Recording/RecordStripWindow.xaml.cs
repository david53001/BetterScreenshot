using System.Windows;
using System.Windows.Media;
using BetterScreenshot.App.Controls;
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
        ControlRow.Children.Add(IconToggle("speaker", "Record system audio", _settings.Recording.SystemAudio,
            on => Persist(_settings.Recording with { SystemAudio = on })));
        ControlRow.Children.Add(IconToggle("mic", "Record microphone", _settings.Recording.Microphone,
            on => Persist(_settings.Recording with { Microphone = on })));
        ControlRow.Children.Add(IconToggle("video", "Show camera bubble", _settings.Recording.Camera,
            on => Persist(_settings.Recording with { Camera = on })));
        ControlRow.Children.Add(Separator());
        ControlRow.Children.Add(IconButton("close", "Cancel", () => OnCancel?.Invoke()));
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

    private static Button IconToggle(string iconKey, string tip, bool initial, Action<bool> onChanged)
    {
        bool state = initial;
        var icon = new IconPresenter { IconKey = iconKey, Width = 18, Height = 18 };
        var b = new Button
        {
            Content = icon,
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
            icon.Brush = state ? GlyphOn : GlyphOff;
        }
        Apply();
        b.Click += (_, _) => { state = !state; Apply(); onChanged(state); };
        return b;
    }

    private static Button IconButton(string iconKey, string tip, Action onClick)
    {
        var b = new Button
        {
            Content = new IconPresenter { IconKey = iconKey, Brush = GlyphOff, Width = 18, Height = 18 },
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

    private static UIElement Separator() => new Border
    {
        Width = 1,
        Height = 22,
        Background = new SolidColorBrush(Color.FromRgb(0xDD, 0xDD, 0xDD)),
        Margin = new Thickness(6, 0, 6, 0),
        VerticalAlignment = VerticalAlignment.Center,
    };
}
