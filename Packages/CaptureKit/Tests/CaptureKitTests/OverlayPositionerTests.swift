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
    TestCase("stackedOriginIndexZeroMatchesOrigin") { t in
        let size = CGSize(width: 220, height: 168)
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let base = OverlayPositioner.origin(corner: .bottomRight, overlaySize: size,
                                            screenFrame: frame, margin: 24)
        let stacked = OverlayPositioner.stackedOrigin(corner: .bottomRight, overlaySize: size,
                                                      screenFrame: frame, margin: 24, index: 0)
        t.equal(stacked, base)
    },
    TestCase("bottomCornersStackUpward") { t in
        let size = CGSize(width: 220, height: 168)
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let s0 = OverlayPositioner.stackedOrigin(corner: .bottomRight, overlaySize: size,
                                                 screenFrame: frame, margin: 24, index: 0)
        let s1 = OverlayPositioner.stackedOrigin(corner: .bottomRight, overlaySize: size,
                                                 screenFrame: frame, margin: 24, index: 1)
        t.approxEqual(s1.x, s0.x)
        t.approxEqual(s1.y, s0.y + CGFloat(168 + 12))   // one slot above, 12 pt gap
    },
    TestCase("topCornersStackDownward") { t in
        let size = CGSize(width: 220, height: 168)
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let s0 = OverlayPositioner.stackedOrigin(corner: .topLeft, overlaySize: size,
                                                 screenFrame: frame, margin: 24, index: 0)
        let s1 = OverlayPositioner.stackedOrigin(corner: .topLeft, overlaySize: size,
                                                 screenFrame: frame, margin: 24, index: 1)
        t.approxEqual(s1.x, s0.x)
        t.approxEqual(s1.y, s0.y - CGFloat(168 + 12))
    },
    TestCase("variableStackBottomRightPacksByActualHeight") { t in
        let f = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let sizes = [CGSize(width: 210, height: 150), CGSize(width: 210, height: 280), CGSize(width: 210, height: 200)]
        let os = OverlayPositioner.stackedOrigins(corner: .bottomRight, sizes: sizes, screenFrame: f, margin: 24, spacing: 12)
        t.equal(os.count, 3)
        t.approxEqual(Double(os[0].x), Double(1000 - 210 - 24), tol: 0.001)
        t.approxEqual(Double(os[0].y), 24, tol: 0.001)
        t.approxEqual(Double(os[1].y), Double(24 + 150 + 12), tol: 0.001)
        t.approxEqual(Double(os[2].y), Double(24 + 150 + 12 + 280 + 12), tol: 0.001)
    },
    TestCase("variableStackTopLeftStacksDownward") { t in
        let f = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let sizes = [CGSize(width: 210, height: 150), CGSize(width: 210, height: 200)]
        let os = OverlayPositioner.stackedOrigins(corner: .topLeft, sizes: sizes, screenFrame: f, margin: 24, spacing: 12)
        t.approxEqual(Double(os[0].x), 24, tol: 0.001)
        t.approxEqual(Double(os[0].y), Double(800 - 24 - 150), tol: 0.001)
        t.approxEqual(Double(os[1].y), Double(800 - 24 - 150 - 12 - 200), tol: 0.001)
    },
]
