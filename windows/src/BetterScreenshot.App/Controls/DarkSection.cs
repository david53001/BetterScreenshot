using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using Colors = System.Windows.Media.Colors;

namespace BetterScreenshot.App.Controls;

/// <summary>
/// A titled dark card (JVoice "DarkSection"). A templated <see cref="ContentControl"/> (NOT a
/// UserControl) so its Content keeps the declaring file's namescope — letting a settings view name
/// elements inside a section. The visual (glowing accent dot + UPPERCASED title + hairline divider +
/// padded content) is the implicit Style in <c>Resources/Theme.xaml</c>.
/// </summary>
public sealed class DarkSection : ContentControl
{
    public static readonly DependencyProperty HeaderTextProperty =
        DependencyProperty.Register(nameof(HeaderText), typeof(string), typeof(DarkSection),
            new FrameworkPropertyMetadata("", FrameworkPropertyMetadataOptions.None, null, CoerceUpper));

    /// <summary>Displayed UPPERCASED (coerced on set, so the TemplateBinding sees the upper form).</summary>
    public string HeaderText
    {
        get => (string)GetValue(HeaderTextProperty);
        set => SetValue(HeaderTextProperty, value);
    }

    private static object CoerceUpper(DependencyObject d, object value)
        => ((string)value).ToUpperInvariant();

    public static readonly DependencyProperty AccentBrushProperty =
        DependencyProperty.Register(nameof(AccentBrush), typeof(Brush), typeof(DarkSection),
            new PropertyMetadata(Brushes.White, OnAccentChanged));

    /// <summary>The header dot color. All sections are white in the monochrome scheme.</summary>
    public Brush AccentBrush
    {
        get => (Brush)GetValue(AccentBrushProperty);
        set => SetValue(AccentBrushProperty, value);
    }

    public static readonly DependencyProperty AccentGlowColorProperty =
        DependencyProperty.Register(nameof(AccentGlowColor), typeof(Color), typeof(DarkSection),
            new PropertyMetadata(Colors.White));

    /// <summary>Kept in sync with <see cref="AccentBrush"/> so the dot's DropShadow glow matches.</summary>
    public Color AccentGlowColor
    {
        get => (Color)GetValue(AccentGlowColorProperty);
        set => SetValue(AccentGlowColorProperty, value);
    }

    private static void OnAccentChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is DarkSection s && e.NewValue is SolidColorBrush b)
            s.AccentGlowColor = b.Color;
    }
}
