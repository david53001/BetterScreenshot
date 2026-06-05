import AppKit

public struct CounterAnnotation: Annotation {
    public let id = UUID()
    public var style = AnnotationStyle.default
    public var number: Int
    public var origin: CGPoint   // top-left of the badge
    public init(number: Int, origin: CGPoint, style: AnnotationStyle = .default) {
        self.number = number; self.origin = origin; self.style = style
    }
    /// A badge centered on `point` (clicks feel anchored to the cursor).
    public static func centered(on point: CGPoint, number: Int,
                                style: AnnotationStyle = .default) -> CounterAnnotation {
        var c = CounterAnnotation(number: number, origin: point, style: style)
        c.origin = CGPoint(x: point.x - c.diameter / 2, y: point.y - c.diameter / 2)
        return c
    }
    public var diameter: CGFloat { max(28, style.fontSize * 1.6) }
    public func boundingBox() -> CGRect {
        CGRect(origin: origin, size: CGSize(width: diameter, height: diameter))
    }
    public func moved(by d: CGVector) -> any Annotation {
        var c = self; c.origin = CGPoint(x: origin.x + d.dx, y: origin.y + d.dy); return c
    }
    public func draw() {
        let rect = boundingBox()
        style.strokeColor.nsColor.setFill()
        NSBezierPath(ovalIn: rect).fill()
        let s = "\(number)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: diameter * 0.55, weight: .bold),
            .foregroundColor: NSColor.white]
        let size = NSAttributedString(string: s, attributes: attrs).size()
        let p = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        NSAttributedString(string: s, attributes: attrs).draw(at: p)
    }
}
