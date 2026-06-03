import AppKit

public struct RectangleAnnotation: Annotation {
    public let id = UUID()
    public var style = AnnotationStyle.default
    public var frame: CGRect
    public var filled: Bool
    public init(frame: CGRect, filled: Bool, style: AnnotationStyle = .default) {
        self.frame = frame; self.filled = filled; self.style = style
    }
    public func boundingBox() -> CGRect { frame }
    public func moved(by d: CGVector) -> any Annotation {
        var c = self; c.frame = frame.offsetBy(dx: d.dx, dy: d.dy); return c
    }
    public func draw() {
        let path = NSBezierPath(rect: frame)
        if filled { style.fillColor.nsColor.setFill(); path.fill() }
        style.strokeColor.nsColor.setStroke(); path.lineWidth = style.lineWidth; path.stroke()
    }
}

public struct FilledRectangleAnnotation: Annotation {
    public let id = UUID()
    public var style = AnnotationStyle.default
    public var frame: CGRect
    public init(frame: CGRect, style: AnnotationStyle = .default) {
        self.frame = frame; self.style = style
    }
    public func boundingBox() -> CGRect { frame }
    public func moved(by d: CGVector) -> any Annotation {
        var c = self; c.frame = frame.offsetBy(dx: d.dx, dy: d.dy); return c
    }
    public func draw() {
        style.strokeColor.nsColor.setFill()
        NSBezierPath(rect: frame).fill()
    }
}

public struct EllipseAnnotation: Annotation {
    public let id = UUID()
    public var style = AnnotationStyle.default
    public var frame: CGRect
    public init(frame: CGRect, style: AnnotationStyle = .default) {
        self.frame = frame; self.style = style
    }
    public func boundingBox() -> CGRect { frame }
    public func moved(by d: CGVector) -> any Annotation {
        var c = self; c.frame = frame.offsetBy(dx: d.dx, dy: d.dy); return c
    }
    public func draw() {
        let path = NSBezierPath(ovalIn: frame)
        style.strokeColor.nsColor.setStroke(); path.lineWidth = style.lineWidth; path.stroke()
    }
}

public struct LineAnnotation: Annotation {
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
    }
    public func moved(by d: CGVector) -> any Annotation {
        var c = self
        c.start = CGPoint(x: start.x + d.dx, y: start.y + d.dy)
        c.end = CGPoint(x: end.x + d.dx, y: end.y + d.dy)
        return c
    }
    public func draw() {
        let path = NSBezierPath()
        path.move(to: start); path.line(to: end)
        style.strokeColor.nsColor.setStroke(); path.lineWidth = style.lineWidth; path.stroke()
    }
}
