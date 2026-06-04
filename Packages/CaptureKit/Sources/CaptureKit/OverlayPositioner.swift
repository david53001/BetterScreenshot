import CoreGraphics

public enum OverlayPositioner {
    /// Returns the Cocoa (bottom-left origin) origin for an overlay window in a screen corner.
    public static func origin(corner: OverlayCorner, overlaySize: CGSize,
                              screenFrame: CGRect, margin: CGFloat) -> CGPoint {
        let leftX = screenFrame.minX + margin
        let rightX = screenFrame.maxX - overlaySize.width - margin
        let bottomY = screenFrame.minY + margin
        let topY = screenFrame.maxY - overlaySize.height - margin
        switch corner {
        case .topLeft:     return CGPoint(x: leftX,  y: topY)
        case .topRight:    return CGPoint(x: rightX, y: topY)
        case .bottomLeft:  return CGPoint(x: leftX,  y: bottomY)
        case .bottomRight: return CGPoint(x: rightX, y: bottomY)
        }
    }

    /// Origin for the overlay at stack position `index` (0 = at the corner;
    /// higher indexes step away from the screen edge so overlays pile up
    /// one over the other with `spacing` between them).
    public static func stackedOrigin(corner: OverlayCorner, overlaySize: CGSize,
                                     screenFrame: CGRect, margin: CGFloat,
                                     index: Int, spacing: CGFloat = 12) -> CGPoint {
        var o = origin(corner: corner, overlaySize: overlaySize,
                       screenFrame: screenFrame, margin: margin)
        let offset = CGFloat(index) * (overlaySize.height + spacing)
        switch corner {
        case .bottomLeft, .bottomRight: o.y += offset   // stack upward
        case .topLeft, .topRight:       o.y -= offset   // stack downward
        }
        return o
    }
}
