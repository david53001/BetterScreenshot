using BetterScreenshot.Core;

namespace BetterScreenshot.Editor;

/// <summary>
/// Pure arrow geometry: the two wing points of the arrowhead triangle, and where the shaft should end so its
/// round cap does not bleed past the arrowhead. Head half-angle defaults to 28°.
/// </summary>
public static class ArrowGeometry
{
    /// <summary>
    /// The two wing points of the arrowhead at <paramref name="end"/>, each <paramref name="length"/> from the tip,
    /// splayed ±<paramref name="halfAngleDegrees"/> from the shaft direction.
    /// </summary>
    public static (PxPoint Left, PxPoint Right) HeadWings(PxPoint start, PxPoint end, double length, double halfAngleDegrees = 28)
    {
        double dx = end.X - start.X, dy = end.Y - start.Y;
        double len = Math.Sqrt(dx * dx + dy * dy);
        if (len < 1e-9) return (end, end);

        double ux = dx / len, uy = dy / len; // forward unit vector
        double ha = halfAngleDegrees * Math.PI / 180.0;

        var left = end.Offset(length * RotX(ux, uy, Math.PI - ha), length * RotY(ux, uy, Math.PI - ha));
        var right = end.Offset(length * RotX(ux, uy, Math.PI + ha), length * RotY(ux, uy, Math.PI + ha));
        return (left, right);
    }

    /// <summary>
    /// Where the shaft should stop: back from the tip by the arrowhead depth (headLength·cos(halfAngle)). For a
    /// short arrow whose head would be longer than the shaft, this clamps to <paramref name="start"/>.
    /// </summary>
    public static PxPoint ShaftEnd(PxPoint start, PxPoint end, double headLength, double halfAngleDegrees = 28)
    {
        double dx = end.X - start.X, dy = end.Y - start.Y;
        double len = Math.Sqrt(dx * dx + dy * dy);
        if (len < 1e-9) return start;

        double headDepth = headLength * Math.Cos(halfAngleDegrees * Math.PI / 180.0);
        double shaftLen = len - headDepth;
        if (shaftLen <= 0) return start;

        double ux = dx / len, uy = dy / len;
        return new PxPoint(start.X + ux * shaftLen, start.Y + uy * shaftLen);
    }

    private static double RotX(double ux, double uy, double theta) => ux * Math.Cos(theta) - uy * Math.Sin(theta);
    private static double RotY(double ux, double uy, double theta) => ux * Math.Sin(theta) + uy * Math.Cos(theta);
}
