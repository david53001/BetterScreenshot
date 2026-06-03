import CoreGraphics
import Foundation

public protocol Annotation {
    var id: UUID { get }
    var style: AnnotationStyle { get set }
    func boundingBox() -> CGRect
    /// Draws into the CURRENT NSGraphicsContext (flipped, top-left origin, image-pixel units).
    func draw()
    func moved(by delta: CGVector) -> any Annotation
}

public extension Annotation {
    /// Lenient v1 hit-test: a few px of slop around the bounding box.
    func hitTest(_ point: CGPoint) -> Bool {
        boundingBox().insetBy(dx: -6, dy: -6).contains(point)
    }
}
