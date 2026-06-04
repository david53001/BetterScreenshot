import TestKit
import CoreGraphics
import Foundation
@testable import EditorKit

private struct StubAnnotation: Annotation {
    let id = UUID()
    var style = AnnotationStyle.default
    var box: CGRect
    func boundingBox() -> CGRect { box }
    func draw() {}
    func moved(by d: CGVector) -> any Annotation {
        var c = self; c.box = box.offsetBy(dx: d.dx, dy: d.dy); return c
    }
}

private func makeBase() -> CGImage {
    let ctx = CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ctx.makeImage()!
}

let editorDocumentTests: [TestCase] = [
    TestCase("addAndCount") { t in
        var doc = EditorDocument(baseImage: makeBase())
        doc.add(StubAnnotation(box: CGRect(x: 0, y: 0, width: 4, height: 4)))
        t.equal(doc.annotations.count, 1)
    },
    TestCase("topmostHitReturnsLastAdded") { t in
        var doc = EditorDocument(baseImage: makeBase())
        let a = StubAnnotation(box: CGRect(x: 0, y: 0, width: 8, height: 8))
        let b = StubAnnotation(box: CGRect(x: 0, y: 0, width: 8, height: 8))
        doc.add(a); doc.add(b)
        t.equal(doc.topmostHit(at: CGPoint(x: 4, y: 4)), b.id) // b drawn last = on top
    },
    TestCase("moveById") { t in
        var doc = EditorDocument(baseImage: makeBase())
        let a = StubAnnotation(box: CGRect(x: 0, y: 0, width: 4, height: 4))
        doc.add(a)
        doc.move(id: a.id, by: CGVector(dx: 5, dy: 3))
        t.equal(doc.annotations[0].boundingBox(), CGRect(x: 5, y: 3, width: 4, height: 4))
    },
    TestCase("removeAndReorder") { t in
        var doc = EditorDocument(baseImage: makeBase())
        let a = StubAnnotation(box: .zero), b = StubAnnotation(box: .zero)
        doc.add(a); doc.add(b)
        doc.bringToFront(id: a.id)
        t.equal(doc.annotations.last?.id, a.id)
        doc.remove(id: b.id)
        t.equal(doc.annotations.count, 1)
    },
    TestCase("idsIntersectingReturnsOnlyOverlapping") { t in
        // Marquee drag-select: only annotations whose box overlaps the rect.
        var doc = EditorDocument(baseImage: makeBase())
        let a = StubAnnotation(box: CGRect(x: 0, y: 0, width: 4, height: 4))
        let b = StubAnnotation(box: CGRect(x: 20, y: 20, width: 4, height: 4))
        doc.add(a); doc.add(b)
        let hit = doc.ids(intersecting: CGRect(x: 0, y: 0, width: 10, height: 10))
        t.equal(hit.count, 1)
        t.isTrue(hit.contains(a.id))
        t.isTrue(!hit.contains(b.id))
    },
    TestCase("idsIntersectingReturnsAllWhenMarqueeCoversEverything") { t in
        var doc = EditorDocument(baseImage: makeBase())
        let a = StubAnnotation(box: CGRect(x: 0, y: 0, width: 4, height: 4))
        let b = StubAnnotation(box: CGRect(x: 20, y: 20, width: 4, height: 4))
        doc.add(a); doc.add(b)
        let hit = doc.ids(intersecting: CGRect(x: 0, y: 0, width: 100, height: 100))
        t.equal(hit.count, 2)
    },
]
