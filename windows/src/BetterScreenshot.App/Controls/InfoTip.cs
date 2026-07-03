using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
// Disambiguate WPF types from the WinForms types the App project also references (for the tray NotifyIcon).
using Brush = System.Windows.Media.Brush;
using Color = System.Windows.Media.Color;
using Cursors = System.Windows.Input.Cursors;
using FontFamily = System.Windows.Media.FontFamily;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using ToolTip = System.Windows.Controls.ToolTip;
using ToolTipEventArgs = System.Windows.Controls.ToolTipEventArgs;
using ToolTipService = System.Windows.Controls.ToolTipService;
using VerticalAlignment = System.Windows.VerticalAlignment;

namespace BetterScreenshot.App.Controls;

/// <summary>
/// A small circular "ⓘ" affordance placed next to a setting. Hovering it reveals a rich, theme-styled tooltip
/// that explains what the setting does and gives a concrete example — so a confusing option is self-documenting.
/// Purely informational: it reads three strings (<see cref="Title"/> / <see cref="Explanation"/> /
/// <see cref="Example"/>) and changes nothing. Built entirely in code (no XAML template) so it drops in anywhere
/// with just the three attributes.
/// </summary>
public sealed class InfoTip : Border
{
    public static readonly DependencyProperty TitleProperty =
        DependencyProperty.Register(nameof(Title), typeof(string), typeof(InfoTip), new PropertyMetadata(""));

    public static readonly DependencyProperty ExplanationProperty =
        DependencyProperty.Register(nameof(Explanation), typeof(string), typeof(InfoTip), new PropertyMetadata(""));

    public static readonly DependencyProperty ExampleProperty =
        DependencyProperty.Register(nameof(Example), typeof(string), typeof(InfoTip), new PropertyMetadata(""));

    /// <summary>Bold heading of the tooltip — normally the setting's name.</summary>
    public string Title { get => (string)GetValue(TitleProperty); set => SetValue(TitleProperty, value); }

    /// <summary>Plain-language description of what the setting does.</summary>
    public string Explanation { get => (string)GetValue(ExplanationProperty); set => SetValue(ExplanationProperty, value); }

    /// <summary>A concrete example, shown prefixed with "e.g." on its own line. Optional.</summary>
    public string Example { get => (string)GetValue(ExampleProperty); set => SetValue(ExampleProperty, value); }

    private static readonly Brush IdleFill = Frozen(Color.FromArgb(0x1F, 0xFF, 0xFF, 0xFF));
    private static readonly Brush HoverFill = Frozen(Color.FromArgb(0x40, 0xFF, 0xFF, 0xFF));
    private static readonly Brush RingBrush = Frozen(Color.FromArgb(0x40, 0xFF, 0xFF, 0xFF));
    private static readonly Brush GlyphBrush = Frozen(Color.FromArgb(0xCC, 0xFF, 0xFF, 0xFF));

    public InfoTip()
    {
        Width = 16;
        Height = 16;
        CornerRadius = new CornerRadius(8);
        Background = IdleFill;
        BorderBrush = RingBrush;
        BorderThickness = new Thickness(1);
        Cursor = Cursors.Arrow; // hover-only affordance — keep the normal pointer, not the Help "?" cursor
        VerticalAlignment = VerticalAlignment.Center;
        HorizontalAlignment = HorizontalAlignment.Left;
        SnapsToDevicePixels = true;
        Focusable = false;

        Child = new TextBlock
        {
            Text = "i",
            FontFamily = new FontFamily("Georgia, Cambria, Times New Roman, serif"),
            FontStyle = FontStyles.Italic,
            FontWeight = FontWeights.Bold,
            FontSize = 10.5,
            Foreground = GlyphBrush,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, -1, 0, 0),
        };

        MouseEnter += (_, _) => Background = HoverFill;
        MouseLeave += (_, _) => Background = IdleFill;

        // Fast to appear, generous time to read, and re-openable without the WPF re-show delay.
        ToolTipService.SetInitialShowDelay(this, 120);
        ToolTipService.SetShowDuration(this, 60000);
        ToolTipService.SetBetweenShowDelay(this, 0);
        ToolTip = new ToolTip { Padding = new Thickness(0) }; // chrome comes from the implicit ToolTip style
        ToolTipOpening += BuildTip;
    }

    private void BuildTip(object sender, ToolTipEventArgs e)
    {
        if (ToolTip is not ToolTip tip) return;

        var panel = new StackPanel { MaxWidth = 300 };

        if (!string.IsNullOrWhiteSpace(Title))
        {
            panel.Children.Add(new TextBlock
            {
                Text = Title,
                FontWeight = FontWeights.SemiBold,
                FontSize = 12.5,
                Foreground = TextBrush("Theme.TextBrush", Color.FromRgb(0xF5, 0xF5, 0xF7)),
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 0, 0, 4),
            });
        }

        panel.Children.Add(new TextBlock
        {
            Text = Explanation,
            FontSize = 11.5,
            Foreground = TextBrush("Theme.TextW85", Color.FromRgb(0xD9, 0xD9, 0xD9)),
            TextWrapping = TextWrapping.Wrap,
            LineHeight = 16,
        });

        if (!string.IsNullOrWhiteSpace(Example))
        {
            panel.Children.Add(new TextBlock
            {
                Text = "e.g. " + Example,
                FontSize = 11,
                FontStyle = FontStyles.Italic,
                Foreground = TextBrush("Theme.SubtleTextBrush", Color.FromRgb(0x8E, 0x8E, 0x93)),
                TextWrapping = TextWrapping.Wrap,
                LineHeight = 15,
                Margin = new Thickness(0, 6, 0, 0),
            });
        }

        tip.Content = panel;
    }

    /// <summary>Theme brush if present (so the tip tracks the app palette), else a literal fallback.</summary>
    private Brush TextBrush(string resourceKey, Color fallback)
        => TryFindResource(resourceKey) as Brush ?? Frozen(fallback);

    private static Brush Frozen(Color c)
    {
        var b = new SolidColorBrush(c);
        b.Freeze();
        return b;
    }
}
