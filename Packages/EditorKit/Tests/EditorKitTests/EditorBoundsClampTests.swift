import TestKit
import CoreGraphics
@testable import EditorKit

let editorBoundsClampTests: [TestCase] = [
    TestCase("pointClampInside") { t in
        t.equal(EditorBoundsClamp.point(CGPoint(x: 50, y: 60), into: CGSize(width: 100, height: 100)), CGPoint(x: 50, y: 60))
    },
    TestCase("pointClampOutside") { t in
        t.equal(EditorBoundsClamp.point(CGPoint(x: -5, y: 130), into: CGSize(width: 100, height: 100)), CGPoint(x: 0, y: 100))
    },
    TestCase("boxTranslatedToStayInside") { t in
        let b = EditorBoundsClamp.box(CGRect(x: 90, y: 90, width: 30, height: 30), into: CGSize(width: 100, height: 100))
        t.equal(b, CGRect(x: 70, y: 70, width: 30, height: 30))
    },
    TestCase("boxLargerThanImagePinsToOrigin") { t in
        let b = EditorBoundsClamp.box(CGRect(x: -50, y: -50, width: 200, height: 200), into: CGSize(width: 100, height: 100))
        t.equal(b, CGRect(x: 0, y: 0, width: 200, height: 200))
    },
]
