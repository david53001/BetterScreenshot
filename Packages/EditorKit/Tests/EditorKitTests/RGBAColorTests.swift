import TestKit
import CoreGraphics
@testable import EditorKit

let rgbaColorTests: [TestCase] = [
    TestCase("cgColorComponentsMatch") { t in
        let c = RGBAColor(r: 1, g: 0.5, b: 0, a: 0.8)
        let cg = c.cgColor
        t.approxEqual(Double(cg.components?[0] ?? -1), 1, tol: 0.001)
        t.approxEqual(Double(cg.components?[1] ?? -1), 0.5, tol: 0.001)
        t.approxEqual(Double(cg.components?[3] ?? -1), 0.8, tol: 0.001)
    },
    TestCase("defaultStyleIsRed") { t in
        t.equal(AnnotationStyle.default.lineWidth, 4)
        t.approxEqual(AnnotationStyle.default.strokeColor.r, 1, tol: 0.001)
    },
]
