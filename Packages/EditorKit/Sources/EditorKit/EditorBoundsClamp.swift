import CoreGraphics

public enum EditorBoundsClamp {
    public static func point(_ p: CGPoint, into size: CGSize) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), size.width), y: min(max(p.y, 0), size.height))
    }

    /// Translate (not shrink) a box so it stays within [0,w]x[0,h]; if larger than the image, pin origin to 0.
    public static func box(_ r: CGRect, into size: CGSize) -> CGRect {
        var x = r.origin.x, y = r.origin.y
        if r.width <= size.width { x = min(max(x, 0), size.width - r.width) } else { x = 0 }
        if r.height <= size.height { y = min(max(y, 0), size.height - r.height) } else { y = 0 }
        return CGRect(x: x, y: y, width: r.width, height: r.height)
    }
}
