import CoreGraphics

public enum QuickAccessCardSize {
    public static let width: CGFloat = 210
    public static let minHeight: CGFloat = 150
    public static let maxHeight: CGFloat = 280

    public static func contentSize(imagePixelWidth w: Int, imagePixelHeight h: Int) -> CGSize {
        let aspect: CGFloat = h > 0 ? CGFloat(w) / CGFloat(h) : 16.0/9.0
        let raw = width / (aspect == 0 ? 16.0/9.0 : aspect)
        let clamped = min(max(raw, minHeight), maxHeight)
        return CGSize(width: width, height: clamped)
    }
}
