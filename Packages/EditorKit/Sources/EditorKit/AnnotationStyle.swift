import CoreGraphics

public struct AnnotationStyle: Equatable {
    public var strokeColor: RGBAColor
    public var fillColor: RGBAColor
    public var lineWidth: CGFloat
    public var fontSize: CGFloat

    public init(strokeColor: RGBAColor, fillColor: RGBAColor,
                lineWidth: CGFloat, fontSize: CGFloat) {
        self.strokeColor = strokeColor; self.fillColor = fillColor
        self.lineWidth = lineWidth; self.fontSize = fontSize
    }

    public static let `default` = AnnotationStyle(
        strokeColor: RGBAColor(r: 1, g: 0.23, b: 0.19, a: 1),
        fillColor: RGBAColor(r: 1, g: 0.23, b: 0.19, a: 0.25),
        lineWidth: 4, fontSize: 24)
}
