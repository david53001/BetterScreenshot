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
    TestCase("shaftEndStopsAtArrowheadBase") { t in
        // Horizontal arrow (0,0)→(100,0), head length 30, half-angle 28°.
        // The shaft must end one head-depth (length·cos28°) short of the tip.
        let e = ArrowGeometry.shaftEnd(start: CGPoint(x: 0, y: 0),
                                       end: CGPoint(x: 100, y: 0),
                                       headLength: 30, halfAngleDegrees: 28)
        t.approxEqual(Double(e.x), Double(100 - 30 * cos(28 * CGFloat.pi / 180)), tol: 0.01)
        t.approxEqual(Double(e.y), 0, tol: 0.001)
        t.isTrue(e.x < 100) // never reaches the tip
    },
    TestCase("shaftEndClampsToStartForShortArrow") { t in
        // Arrow shorter than the head: the shaft collapses to the start (no
        // negative-length shaft pointing backwards).
        let e = ArrowGeometry.shaftEnd(start: CGPoint(x: 0, y: 0),
                                       end: CGPoint(x: 10, y: 0),
                                       headLength: 30, halfAngleDegrees: 28)
        t.approxEqual(Double(e.x), 0, tol: 0.001)
        t.approxEqual(Double(e.y), 0, tol: 0.001)
    },
]
