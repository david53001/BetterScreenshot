namespace BetterScreenshot.Core;

/// <summary>A 2D point in pixel/logical space (top-left origin, like all Windows coordinates).</summary>
public readonly record struct PxPoint(double X, double Y)
{
    public PxPoint Offset(double dx, double dy) => new(X + dx, Y + dy);
}

/// <summary>A width/height pair.</summary>
public readonly record struct PxSize(double Width, double Height)
{
    public bool IsEmpty => Width <= 0 || Height <= 0;
}

/// <summary>
/// An axis-aligned rectangle with top-left origin (X,Y) and Width/Height. All BetterScreenshot geometry
/// uses top-left origin on Windows (the macOS app flipped between Cocoa bottom-left and image top-left;
/// we do not). <see cref="Contains"/> is half-open: [X, Right) × [Y, Bottom).
/// </summary>
public readonly record struct PxRect(double X, double Y, double Width, double Height)
{
    public double Right => X + Width;
    public double Bottom => Y + Height;
    public PxPoint Center => new(X + Width / 2, Y + Height / 2);
    public PxSize Size => new(Width, Height);
    public bool IsEmpty => Width <= 0 || Height <= 0;

    public static PxRect FromLtrb(double left, double top, double right, double bottom) =>
        new(left, top, right - left, bottom - top);

    public bool Contains(PxPoint p) => p.X >= X && p.X < Right && p.Y >= Y && p.Y < Bottom;

    /// <summary>Smallest integral rect that contains this one (floor origin, ceil far edges) — mirrors CGRect.integral.</summary>
    public PxRect Integral() =>
        FromLtrb(Math.Floor(X), Math.Floor(Y), Math.Ceiling(X + Width), Math.Ceiling(Y + Height));

    /// <summary>Intersection with another rect, or an empty (0,0,0,0) rect if they do not overlap.</summary>
    public PxRect Intersection(PxRect o)
    {
        double left = Math.Max(X, o.X), top = Math.Max(Y, o.Y);
        double right = Math.Min(Right, o.Right), bottom = Math.Min(Bottom, o.Bottom);
        return (right <= left || bottom <= top) ? new PxRect(0, 0, 0, 0) : FromLtrb(left, top, right, bottom);
    }

    public PxRect Union(PxRect o) =>
        FromLtrb(Math.Min(X, o.X), Math.Min(Y, o.Y), Math.Max(Right, o.Right), Math.Max(Bottom, o.Bottom));

    /// <summary>Same size, translated by (dx, dy).</summary>
    public PxRect Offset(double dx, double dy) => new(X + dx, Y + dy, Width, Height);
}
