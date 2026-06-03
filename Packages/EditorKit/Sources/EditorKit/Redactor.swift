import CoreImage
import CoreGraphics

public enum Redactor {
    private static let context = CIContext(options: nil)

    private static func patch(_ base: CGImage, region: CGRect,
                              _ transform: (CIImage) -> CIImage) -> CGImage? {
        let r = region.integral
        guard r.width >= 1, r.height >= 1 else { return nil }
        let full = CIImage(cgImage: base)
        // CIImage origin is bottom-left; convert top-left region → bottom-left.
        let blOrigin = CGRect(x: r.minX,
                              y: CGFloat(base.height) - r.maxY,
                              width: r.width, height: r.height)
        let cropped = full.cropped(to: blOrigin)
        let filtered = transform(cropped).cropped(to: blOrigin)
        return context.createCGImage(filtered, from: blOrigin)
    }

    public static func pixelate(_ base: CGImage, region: CGRect, blockSize: CGFloat) -> CGImage? {
        patch(base, region: region) { img in
            img.applyingFilter("CIPixellate", parameters: [
                kCIInputScaleKey: blockSize,
                kCIInputCenterKey: CIVector(x: region.midX, y: CGFloat(base.height) - region.midY)])
        }
    }

    public static func blur(_ base: CGImage, region: CGRect, radius: CGFloat) -> CGImage? {
        patch(base, region: region) { img in
            img.clampedToExtent().applyingFilter("CIGaussianBlur",
                parameters: [kCIInputRadiusKey: radius])
        }
    }
}
