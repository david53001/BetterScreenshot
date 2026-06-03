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
}
