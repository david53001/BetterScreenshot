import AppKit

public struct TextAnnotation: Annotation {
    public let id = UUID()
    public var style = AnnotationStyle.default
    public var text: String
    public var origin: CGPoint   // top-left
    public init(text: String, origin: CGPoint, style: AnnotationStyle = .default) {
        self.text = text; self.origin = origin; self.style = style
    }
    private var attributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: style.fontSize, weight: .semibold),
         .foregroundColor: style.strokeColor.nsColor]
    }
    public func boundingBox() -> CGRect {
        let size = NSAttributedString(string: text.isEmpty ? " " : text,
                                      attributes: attributes).size()
        return CGRect(origin: origin, size: size)
    }
    public func moved(by d: CGVector) -> any Annotation {
        var c = self; c.origin = CGPoint(x: origin.x + d.dx, y: origin.y + d.dy); return c
    }
    public func draw() {
        if style.textBackground {
            let size = NSAttributedString(string: text.isEmpty ? " " : text,
                                          attributes: attributes).size()
            let textRect = CGRect(origin: origin, size: size)
            let chipRect = textRect.insetBy(dx: -TextChip.horizontalPadding, dy: -TextChip.verticalPadding)
            let sc = style.strokeColor
            let luminance = 0.2126 * sc.r + 0.7152 * sc.g + 0.0722 * sc.b
            let chipColor = TextChip.chipIsDark(forTextLuminance: Double(luminance))
                ? NSColor(red: 0x18 / 255, green: 0x18 / 255, blue: 0x1A / 255, alpha: 1)
                : NSColor(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF6 / 255, alpha: 1)
            let path = NSBezierPath(roundedRect: chipRect, xRadius: TextChip.cornerRadius, yRadius: TextChip.cornerRadius)
            chipColor.setFill()
            path.fill()
        }
        NSAttributedString(string: text, attributes: attributes).draw(at: origin)
    }
}
