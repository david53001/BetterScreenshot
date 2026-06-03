import CoreGraphics

public enum CaptureGeometry {
    /// Convert a rect in Cocoa global coordinates (bottom-left origin, points)
    /// into a top-left-origin pixel rect relative to a captured display image.
    public static func pixelRect(forGlobalRect rect: CGRect,
                                 inDisplayFrame display: CGRect,
                                 scale: CGFloat) -> CGRect {
        let xLocal = (rect.minX - display.minX) * scale
        let yTopLocal = (display.maxY - rect.maxY) * scale
        return CGRect(x: xLocal, y: yTopLocal,
                      width: rect.width * scale, height: rect.height * scale)
    }
}
