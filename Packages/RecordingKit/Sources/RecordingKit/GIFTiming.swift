import Foundation
import CoreGraphics

public enum GIFTiming {
    /// Sample timestamps (seconds) for converting a clip to GIF at `fps`.
    /// Always at least one frame.
    public static func frameTimes(duration: Double, fps: Int) -> [Double] {
        guard duration > 0, fps > 0 else { return [0] }
        let step = 1.0 / Double(fps)
        let count = max(1, Int(duration * Double(fps)))
        return (0..<count).map { Double($0) * step }
    }

    /// Aspect-preserving downscale to `maxWidth`; never upscales.
    public static func outputSize(source: CGSize, maxWidth: CGFloat) -> CGSize {
        guard source.width > maxWidth, source.width > 0 else { return source }
        let scale = maxWidth / source.width
        return CGSize(width: maxWidth, height: (source.height * scale).rounded())
    }
}
