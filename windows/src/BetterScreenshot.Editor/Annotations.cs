using BetterScreenshot.Core;

namespace BetterScreenshot.Editor;

/// <summary>
/// An annotation object living in base-image pixel space (top-left origin). Concrete types hold their own
/// geometry; the WPF <c>DocumentRenderer</c> switches on the concrete type to draw. Kept UI-free so the model
/// is headless-testable.
/// </summary>
public interface IAnnotation
{
    Guid Id { get; }
    AnnotationStyle Style { get; }
    PxRect BoundingBox();
    IAnnotation MovedBy(double dx, double dy);
}

public static class AnnotationExtensions
{
    public const double HitSlop = 6;

    /// <summary>Lenient hit-test: the bounding box inflated by <paramref name="slop"/> on every side.</summary>
    public static bool HitTest(this IAnnotation a, PxPoint p, double slop = HitSlop)
    {
        var b = a.BoundingBox();
        var inflated = new PxRect(b.X - slop, b.Y - slop, b.Width + 2 * slop, b.Height + 2 * slop);
        return inflated.Contains(p);
    }

    internal static PxRect BoundsOfSegment(PxPoint a, PxPoint b) =>
        PxRect.FromLtrb(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y), Math.Max(a.X, b.X), Math.Max(a.Y, b.Y));
}

public sealed record ArrowAnnotation(Guid Id, AnnotationStyle Style, PxPoint Start, PxPoint End) : IAnnotation
{
    public PxRect BoundingBox() => AnnotationExtensions.BoundsOfSegment(Start, End);
    public IAnnotation MovedBy(double dx, double dy) => this with { Start = Start.Offset(dx, dy), End = End.Offset(dx, dy) };
}

public sealed record LineAnnotation(Guid Id, AnnotationStyle Style, PxPoint Start, PxPoint End) : IAnnotation
{
    public PxRect BoundingBox() => AnnotationExtensions.BoundsOfSegment(Start, End);
    public IAnnotation MovedBy(double dx, double dy) => this with { Start = Start.Offset(dx, dy), End = End.Offset(dx, dy) };
}

public sealed record RectangleAnnotation(Guid Id, AnnotationStyle Style, PxRect Frame, bool Filled) : IAnnotation
{
    public PxRect BoundingBox() => Frame;
    public IAnnotation MovedBy(double dx, double dy) => this with { Frame = Frame.Offset(dx, dy) };
}

public sealed record FilledRectangleAnnotation(Guid Id, AnnotationStyle Style, PxRect Frame) : IAnnotation
{
    public PxRect BoundingBox() => Frame;
    public IAnnotation MovedBy(double dx, double dy) => this with { Frame = Frame.Offset(dx, dy) };
}

public sealed record EllipseAnnotation(Guid Id, AnnotationStyle Style, PxRect Frame) : IAnnotation
{
    public PxRect BoundingBox() => Frame;
    public IAnnotation MovedBy(double dx, double dy) => this with { Frame = Frame.Offset(dx, dy) };
}

public sealed record TextAnnotation(Guid Id, AnnotationStyle Style, string Text, PxPoint Origin) : IAnnotation
{
    // Approximate metrics for headless bounds; the WPF renderer measures precisely with FormattedText.
    public PxRect BoundingBox() =>
        new(Origin.X, Origin.Y, Math.Max(1, Text.Length) * Style.FontSize * 0.6, Style.FontSize * 1.2);

    public IAnnotation MovedBy(double dx, double dy) => this with { Origin = Origin.Offset(dx, dy) };
}

public sealed record CounterAnnotation(Guid Id, AnnotationStyle Style, int Number, PxPoint Origin) : IAnnotation
{
    public double Diameter => Math.Max(28, Style.FontSize * 1.6);
    public PxRect BoundingBox() => new(Origin.X, Origin.Y, Diameter, Diameter);
    public IAnnotation MovedBy(double dx, double dy) => this with { Origin = Origin.Offset(dx, dy) };

    /// <summary>Creates a counter badge centered on <paramref name="point"/>.</summary>
    public static CounterAnnotation Centered(PxPoint point, int number, AnnotationStyle style)
    {
        double d = Math.Max(28, style.FontSize * 1.6);
        return new CounterAnnotation(Guid.NewGuid(), style, number, new PxPoint(point.X - d / 2, point.Y - d / 2));
    }
}

public sealed record PixelateAnnotation(Guid Id, AnnotationStyle Style, PxRect Frame, ArgbImage? Patch = null) : IAnnotation
{
    public PxRect BoundingBox() => Frame;
    public IAnnotation MovedBy(double dx, double dy) => this with { Frame = Frame.Offset(dx, dy) };
}

public sealed record BlurAnnotation(Guid Id, AnnotationStyle Style, PxRect Frame, ArgbImage? Patch = null) : IAnnotation
{
    public PxRect BoundingBox() => Frame;
    public IAnnotation MovedBy(double dx, double dy) => this with { Frame = Frame.Offset(dx, dy) };
}
