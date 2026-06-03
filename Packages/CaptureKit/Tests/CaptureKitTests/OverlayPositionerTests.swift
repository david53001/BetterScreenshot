import TestKit
import CoreGraphics
@testable import CaptureKit

let overlayPositionerTests: [TestCase] = [
    TestCase("bottomRight") { t in
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 200, height: 140)
        let o = OverlayPositioner.origin(corner: .bottomRight, overlaySize: size,
                                         screenFrame: screen, margin: 16)
        // x = 1440 - 200 - 16 = 1224; y = 16
        t.equal(o, CGPoint(x: 1224, y: 16))
    },
    TestCase("topLeft") { t in
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 200, height: 140)
        let o = OverlayPositioner.origin(corner: .topLeft, overlaySize: size,
                                         screenFrame: screen, margin: 16)
        // x = 16; y = 900 - 140 - 16 = 744
        t.equal(o, CGPoint(x: 16, y: 744))
    },
    TestCase("topRightWithDisplayOffset") { t in
        let s2 = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let size = CGSize(width: 200, height: 140)
        let o = OverlayPositioner.origin(corner: .topRight, overlaySize: size,
                                         screenFrame: s2, margin: 20)
        // x = 1440 + 1920 - 200 - 20 = 3140; y = 1080 - 140 - 20 = 920
        t.equal(o, CGPoint(x: 3140, y: 920))
    },
]
