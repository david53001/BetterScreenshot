import CoreGraphics

/// Pure geometry for pinned screenshots (all rects in Cocoa global points).
public enum PinGeometry {
    /// Initial pin frame: the image's point size (pixels ÷ backingScale),
    /// shrunk if needed so it fits within maxFraction of the visible frame
    /// (aspect preserved), centered on sourceRect when known (else on the
    /// visible frame), then nudged fully on-screen.
    public static func initialFrame(imagePixelSize: CGSize, backingScale: CGFloat,
                                    visibleFrame: CGRect, sourceRect: CGRect?,
                                    maxFraction: CGFloat = 0.8) -> CGRect {
        var size = CGSize(width: imagePixelSize.width / backingScale,
                          height: imagePixelSize.height / backingScale)
        let scale = min(1, (visibleFrame.width * maxFraction) / size.width,
                        (visibleFrame.height * maxFraction) / size.height)
        size = CGSize(width: size.width * scale, height: size.height * scale)

        let center = sourceRect.map { CGPoint(x: $0.midX, y: $0.midY) }
            ?? CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        var frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                           width: size.width, height: size.height)
        if frame.maxX > visibleFrame.maxX { frame.origin.x = visibleFrame.maxX - frame.width }
        if frame.maxY > visibleFrame.maxY { frame.origin.y = visibleFrame.maxY - frame.height }
        if frame.minX < visibleFrame.minX { frame.origin.x = visibleFrame.minX }
        if frame.minY < visibleFrame.minY { frame.origin.y = visibleFrame.minY }
        return frame
    }

    /// Rescales `current` around its center by `factor`, clamped so the result
    /// stays between minScale× and maxScale× of `naturalSize` (aspect preserved).
    public static func zoomedFrame(current: CGRect, naturalSize: CGSize, factor: CGFloat,
                                   minScale: CGFloat = 0.25, maxScale: CGFloat = 3.0) -> CGRect {
        guard naturalSize.width > 0, naturalSize.height > 0, factor > 0 else { return current }
        let newScale = min(maxScale, max(minScale, (current.width / naturalSize.width) * factor))
        let newSize = CGSize(width: naturalSize.width * newScale,
                             height: naturalSize.height * newScale)
        return CGRect(x: current.midX - newSize.width / 2,
                      y: current.midY - newSize.height / 2,
                      width: newSize.width, height: newSize.height)
    }
}
