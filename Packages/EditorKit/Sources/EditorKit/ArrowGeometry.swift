import CoreGraphics

public enum ArrowGeometry {
    /// The two arrowhead wing points for an arrow from `start` to `end`.
    public static func headWings(start: CGPoint, end: CGPoint,
                                 length: CGFloat, halfAngleDegrees: CGFloat)
        -> (left: CGPoint, right: CGPoint) {
        let dx = end.x - start.x, dy = end.y - start.y
        let angle = atan2(dy, dx)
        let half = halfAngleDegrees * .pi / 180
        let a1 = angle + .pi - half
        let a2 = angle + .pi + half
        let left = CGPoint(x: end.x + length * cos(a1), y: end.y + length * sin(a1))
        let right = CGPoint(x: end.x + length * cos(a2), y: end.y + length * sin(a2))
        return (left, right)
    }

    /// Where the shaft should stop so it ends at the arrowhead's base instead of
    /// the tip — otherwise a thick round line cap pokes out past the tip. The
    /// head's depth along the arrow axis is `headLength·cos(halfAngle)`; the
    /// shaft is clamped so it never points backwards for a very short arrow.
    public static func shaftEnd(start: CGPoint, end: CGPoint,
                                headLength: CGFloat, halfAngleDegrees: CGFloat) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0 else { return start }
        let backset = headLength * cos(halfAngleDegrees * .pi / 180)
        let shaftLen = max(0, len - backset)
        let t = shaftLen / len
        return CGPoint(x: start.x + dx * t, y: start.y + dy * t)
    }
}
