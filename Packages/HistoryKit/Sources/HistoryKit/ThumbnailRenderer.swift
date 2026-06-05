import Foundation
import CoreGraphics
import ImageIO

/// Downscales encoded image data (PNG, TIFF, …) to a JPEG thumbnail whose
/// longest side is at most `maxPixelSize`. Pure data-in/data-out; works
/// headless (probed 2026-06-05 under CLT).
public enum ThumbnailRenderer {
    public static func jpegThumbnail(from imageData: Data,
                                     maxPixelSize: Int = 400,
                                     quality: Double = 0.8) -> Data? {
        guard let src = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out as CFMutableData, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, thumb,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// Pixel size of encoded image data (for tests and sanity checks).
    public static func pixelSize(of imageData: Data) -> CGSize? {
        guard let src = CGImageSourceCreateWithData(imageData as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }
}
