using System.Text.Json;
using System.Text.Json.Serialization;

namespace BetterScreenshot.Editor;

/// <summary>An sRGB color with straight (non-premultiplied) alpha, each channel in [0,1]. JSON-serializable.</summary>
public readonly record struct RGBAColor(double R, double G, double B, double A)
{
    public static RGBAColor FromBytes(byte r, byte g, byte b, byte a = 255) =>
        new(r / 255.0, g / 255.0, b / 255.0, a / 255.0);

    public RGBAColor WithAlpha(double alpha) => this with { A = alpha };
}

/// <summary>
/// The style applied to annotation objects: stroke/fill color, line width, and font size. Persisted as JSON
/// (the editor remembers the last-used style across sessions). Default = red, 4pt line, 24pt font.
/// </summary>
public sealed record AnnotationStyle
{
    public RGBAColor StrokeColor { get; init; }
    public RGBAColor FillColor { get; init; }
    public double LineWidth { get; init; }
    public double FontSize { get; init; }

    /// <summary>
    /// Optional solid background drawn behind text annotations (a rounded "label" chip). <c>null</c> = no
    /// background: text renders directly on the image (the default). Persisted with the rest of the style, so the
    /// last-used choice is sticky. Only text honors this; shapes ignore it.
    /// </summary>
    public RGBAColor? TextBackground { get; init; }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
    };

    /// <summary>Red stroke (1, 0.23, 0.19, 1), a 25%-alpha fill of the same hue, 4pt line, 24pt font.</summary>
    public static AnnotationStyle Default { get; } = CreateDefault();

    private static AnnotationStyle CreateDefault()
    {
        var red = new RGBAColor(1.0, 0.23, 0.19, 1.0);
        return new AnnotationStyle
        {
            StrokeColor = red,
            FillColor = red.WithAlpha(0.25),
            LineWidth = 4,
            FontSize = 24,
        };
    }

    public string ToJson() => JsonSerializer.Serialize(this, JsonOptions);

    public static AnnotationStyle FromJson(string json) =>
        JsonSerializer.Deserialize<AnnotationStyle>(json, JsonOptions)
        ?? throw new JsonException("null annotation style");
}
