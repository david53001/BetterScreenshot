import TestKit
import CoreGraphics
@testable import EditorKit

let arrowGeometryTests: [TestCase] = [
    TestCase("horizontalArrowheadWings") { t in
        // Arrow pointing right: start (0,0) → end (100,0), head length 10, half-angle 30°.
        let (left, right) = ArrowGeometry.headWings(
            start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0),
            length: 10, halfAngleDegrees: 30)
        // Wings sit behind the tip (x < 100) and symmetric about y=0.
        t.isTrue(left.x < 100)
        t.isTrue(right.x < 100)
        t.approxEqual(Double(left.y), Double(-right.y), tol: 0.001)
        t.approxEqual(Double(abs(left.y)), Double(10 * sin(30 * CGFloat.pi / 180)), tol: 0.01)
    },
]
