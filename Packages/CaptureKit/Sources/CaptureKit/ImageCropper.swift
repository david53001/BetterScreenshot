import CoreGraphics

public enum ImageCropper {
    /// Crop with integer pixel rounding, clamped to the image bounds.
    /// Returns nil if the resulting rect has zero area.
    public static func crop(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clamped = rect.integral.intersection(bounds)
        guard clamped.width >= 1, clamped.height >= 1 else { return nil }
        return image.cropping(to: clamped)
    }
}
