import TestKit
import CoreGraphics
@testable import EditorKit

let textAnnotationTests: [TestCase] = [
    TestCase("longerStringHasWiderBox") { t in
        let short = TextAnnotation(text: "Hi", origin: CGPoint(x: 0, y: 0))
        let long = TextAnnotation(text: "Hello world, this is longer", origin: CGPoint(x: 0, y: 0))
        t.isTrue(long.boundingBox().width > short.boundingBox().width)
    },
    TestCase("moveOffsetsOrigin") { t in
        let ta = TextAnnotation(text: "Hi", origin: CGPoint(x: 10, y: 10))
        let m = ta.moved(by: CGVector(dx: 5, dy: 7))
        t.approxEqual(Double(m.boundingBox().minX), 15, tol: 0.5)
        t.approxEqual(Double(m.boundingBox().minY), 17, tol: 0.5)
    },
]
