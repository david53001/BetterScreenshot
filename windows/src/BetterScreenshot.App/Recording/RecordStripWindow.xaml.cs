using System.Windows;
using System.Windows.Media;
using BetterScreenshot.App.Controls;
using BetterScreenshot.Platform;
using BetterScreenshot.Recording;
using Border = System.Windows.Controls.Border;
using Button = System.Windows.Controls.Button;
using Color = System.Windows.Media.Color;
using Cursors = System.Windows.Input.Cursors;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using Orientation = System.Windows.Controls.Orientation;
using Path = System.Windows.Shapes.Path;
using StackPanel = System.Windows.Controls.StackPanel;
using ToggleButton = System.Windows.Controls.Primitives.ToggleButton;
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
    private static readonly SolidColorBrush GlyphOff = new(Color.FromRgb(0xC8, 0xC8, 0xCF));
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
        ToggleButton mp4 = null!, gif = null!;
        void Refresh()
        {
            bool isMp4 = _settings.Recording.Format == RecordingFormat.Mp4;
            mp4.IsChecked = isMp4;
            gif.IsChecked = !isMp4;
            mp4.Foreground = isMp4 ? GlyphOn : GlyphOff;
            gif.Foreground = isMp4 ? GlyphOff : GlyphOn;
        }
        mp4 = Segment("MP4", () => { Persist(_settings.Recording with { Format = RecordingFormat.Mp4 }); Refresh(); });
        gif = Segment("GIF", () => { Persist(_settings.Recording with { Format = RecordingFormat.Gif }); Refresh(); });
        panel.Children.Add(mp4);
        panel.Children.Add(gif);
        Refresh();
        return panel;

        ToggleButton Segment(string text, Action onClick)
        {
            var b = new ToggleButton
            {
                Content = text,
                Style = (Style)FindResource("Theme.ToolButton"),
                Width = 46,
                Height = 28,
                FontSize = 12,
            };
            b.Click += (_, _) => onClick();
            return b;
        }
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

    private ToggleButton IconToggle(string iconKey, string tip, bool initial, Action<bool> onChanged)
    {
        var icon = new IconPresenter { IconKey = iconKey, Width = 18, Height = 18, Brush = initial ? GlyphOn : GlyphOff };
        var b = new ToggleButton
        {
            Content = icon,
            Style = (Style)FindResource("Theme.ToolButton"),
            Width = 34,
            Height = 30,
            Margin = new Thickness(2, 0, 2, 0),
            ToolTip = tip,
            IsChecked = initial,
        };
        System.Windows.Automation.AutomationProperties.SetName(b, tip);
        b.Click += (_, _) =>
        {
            bool on = b.IsChecked == true;
            icon.Brush = on ? GlyphOn : GlyphOff;
            onChanged(on);
        };
        return b;
    }

    private Button IconButton(string iconKey, string tip, Action onClick)
    {
        var b = new Button
        {
            Content = new IconPresenter { IconKey = iconKey, Brush = GlyphOff, Width = 18, Height = 18 },
            Width = 30,
            Height = 30,
            Margin = new Thickness(2, 0, 0, 0),
            ToolTip = tip,
            Cursor = Cursors.Hand,
            Style = (Style)FindResource("Theme.SubtleButton"),
        };
        System.Windows.Automation.AutomationProperties.SetName(b, tip);
        b.Click += (_, _) => onClick();
        return b;
    }

    private static UIElement Separator() => new Border
    {
        Width = 1,
        Height = 22,
        Background = new SolidColorBrush(Color.FromArgb(0x26, 0xFF, 0xFF, 0xFF)),
        Margin = new Thickness(6, 0, 6, 0),
        VerticalAlignment = VerticalAlignment.Center,
    };
}
