import TestKit
import CoreGraphics
@testable import CaptureKit

let selectionClampTests: [TestCase] = [
    TestCase("insideUnchanged") { t in
        let r = CGRect(x: 10, y: 10, width: 50, height: 50)
        t.equal(SelectionClamp.clamp(r, to: CGRect(x: 0, y: 0, width: 100, height: 100)), r)
    },
    TestCase("overflowClipped") { t in
        let r = CGRect(x: 80, y: 80, width: 50, height: 50)
        t.equal(SelectionClamp.clamp(r, to: CGRect(x: 0, y: 0, width: 100, height: 100)),
                CGRect(x: 80, y: 80, width: 20, height: 20))
    },
]
