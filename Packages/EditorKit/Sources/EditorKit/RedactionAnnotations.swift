import AppKit

public struct PixelateAnnotation: Annotation {
    public let id = UUID()
    public var style = AnnotationStyle.default
    public var frame: CGRect
    public let patch: CGImage
    public init(frame: CGRect, patch: CGImage) { self.frame = frame; self.patch = patch }
    public func boundingBox() -> CGRect { frame }
    public func moved(by d: CGVector) -> any Annotation {
        var c = self; c.frame = frame.offsetBy(dx: d.dx, dy: d.dy); return c
    }
    public func draw() {
        NSImage(cgImage: patch, size: frame.size).draw(in: frame)
    }
}

public struct BlurAnnotation: Annotation {
    public let id = UUID()
    public var style = AnnotationStyle.default
    public var frame: CGRect
    public let patch: CGImage
    public init(frame: CGRect, patch: CGImage) { self.frame = frame; self.patch = patch }
    public func boundingBox() -> CGRect { frame }
    public func moved(by d: CGVector) -> any Annotation {
        var c = self; c.frame = frame.offsetBy(dx: d.dx, dy: d.dy); return c
    }
    public func draw() {
        NSImage(cgImage: patch, size: frame.size).draw(in: frame)
    }
}
