import TestKit
import CoreGraphics
@testable import EditorKit

let shapeAnnotationTests: [TestCase] = [
    TestCase("rectangleBoundingBoxAndMove") { t in
        let r = RectangleAnnotation(frame: CGRect(x: 10, y: 20, width: 30, height: 40), filled: false)
        t.equal(r.boundingBox(), CGRect(x: 10, y: 20, width: 30, height: 40))
        let moved = r.moved(by: CGVector(dx: 5, dy: -5))
        t.equal(moved.boundingBox(), CGRect(x: 15, y: 15, width: 30, height: 40))
    },
    TestCase("ellipseHitTestUsesBoundingBox") { t in
        let e = EllipseAnnotation(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        t.isTrue(e.hitTest(CGPoint(x: 10, y: 10)))
        t.isFalse(e.hitTest(CGPoint(x: 200, y: 200)))
    },
    TestCase("lineBoundingBoxSpansEndpoints") { t in
        let l = LineAnnotation(start: CGPoint(x: 5, y: 30), end: CGPoint(x: 25, y: 10))
        let bb = l.boundingBox()
        t.approxEqual(Double(bb.minX), 5, tol: 0.001)
        t.approxEqual(Double(bb.minY), 10, tol: 0.001)
        t.approxEqual(Double(bb.maxX), 25, tol: 0.001)
        t.approxEqual(Double(bb.maxY), 30, tol: 0.001)
    },
]
