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
}
