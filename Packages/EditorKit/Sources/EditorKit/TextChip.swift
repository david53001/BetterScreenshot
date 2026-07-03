import CoreGraphics

public enum TextChip {
    public static let cornerRadius: CGFloat = 4
    public static let horizontalPadding: CGFloat = 6
    public static let verticalPadding: CGFloat = 3
    /// Light text (luminance > 0.5) gets a dark chip; dark text gets a light chip.
    public static func chipIsDark(forTextLuminance lum: Double) -> Bool { lum > 0.5 }
}
