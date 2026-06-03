import AppKit

public struct ArrowAnnotation: Annotation {
    public let id = UUID()
    public var style = AnnotationStyle.default
    public var start: CGPoint
    public var end: CGPoint
    public init(start: CGPoint, end: CGPoint, style: AnnotationStyle = .default) {
        self.start = start; self.end = end; self.style = style
    }
    public func boundingBox() -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(start.x - end.x), height: abs(start.y - end.y))
            .insetBy(dx: -style.lineWidth * 3, dy: -style.lineWidth * 3)
    }
    public func moved(by d: CGVector) -> any Annotation {
        var c = self
        c.start = CGPoint(x: start.x + d.dx, y: start.y + d.dy)
        c.end = CGPoint(x: end.x + d.dx, y: end.y + d.dy)
        return c
    }
    public func draw() {
        let headLen = max(12, style.lineWidth * 3)
        let (left, right) = ArrowGeometry.headWings(start: start, end: end,
                                                    length: headLen, halfAngleDegrees: 28)
        let shaft = NSBezierPath()
        shaft.move(to: start); shaft.line(to: end)
        style.strokeColor.nsColor.setStroke()
        shaft.lineWidth = style.lineWidth; shaft.lineCapStyle = .round; shaft.stroke()

        let head = NSBezierPath()
        head.move(to: end); head.line(to: left); head.line(to: right); head.close()
        style.strokeColor.nsColor.setFill(); head.fill()
    }
}
