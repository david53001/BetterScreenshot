import CoreGraphics
import Foundation

public struct EditorDocument {
    public let baseImage: CGImage
    public private(set) var annotations: [any Annotation] = []

    public var size: CGSize { CGSize(width: baseImage.width, height: baseImage.height) }

    public init(baseImage: CGImage) { self.baseImage = baseImage }

    public mutating func add(_ a: any Annotation) { annotations.append(a) }

    public mutating func remove(id: UUID) { annotations.removeAll { $0.id == id } }

    public func index(of id: UUID) -> Int? { annotations.firstIndex { $0.id == id } }

    public mutating func move(id: UUID, by delta: CGVector) {
        guard let i = index(of: id) else { return }
        annotations[i] = annotations[i].moved(by: delta)
    }

    public mutating func replace(id: UUID, with a: any Annotation) {
        guard let i = index(of: id) else { return }
        annotations[i] = a
    }

    public mutating func bringToFront(id: UUID) {
        guard let i = index(of: id) else { return }
        let a = annotations.remove(at: i); annotations.append(a)
    }

    public mutating func sendToBack(id: UUID) {
        guard let i = index(of: id) else { return }
        let a = annotations.remove(at: i); annotations.insert(a, at: 0)
    }

    /// Topmost (last-drawn) annotation under the point.
    public func topmostHit(at point: CGPoint) -> UUID? {
        for a in annotations.reversed() where a.hitTest(point) { return a.id }
        return nil
    }

    public func nextCounterNumber() -> Int { 1 } // refined in Task 6
}
