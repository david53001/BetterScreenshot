import CoreGraphics

public enum SelectionClamp {
    public static func clamp(_ r: CGRect, to bounds: CGRect) -> CGRect { r.intersection(bounds) }
}
