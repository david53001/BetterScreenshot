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
        NSAttributedString(string: text, attributes: attributes).draw(at: origin)
    }
}
