import TestKit
import CoreGraphics
@testable import OverlayKit

let pinGeometryTests: [TestCase] = [
    TestCase("retinaImageGetsPointSize") { t in
        let f = PinGeometry.initialFrame(
            imagePixelSize: CGSize(width: 400, height: 200), backingScale: 2,
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875), sourceRect: nil)
        t.equal(f.size, CGSize(width: 200, height: 100))
    },
    TestCase("centersOnVisibleFrameWithoutSource") { t in
        let vf = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let f = PinGeometry.initialFrame(imagePixelSize: CGSize(width: 400, height: 200),
                                         backingScale: 2, visibleFrame: vf, sourceRect: nil)
        t.approxEqual(f.midX, vf.midX)
        t.approxEqual(f.midY, vf.midY)
    },
    TestCase("centersOnSourceRect") { t in
        let f = PinGeometry.initialFrame(
            imagePixelSize: CGSize(width: 200, height: 100), backingScale: 2,
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
            sourceRect: CGRect(x: 300, y: 300, width: 100, height: 50))
        t.approxEqual(f.midX, 350)
        t.approxEqual(f.midY, 325)
    },
    TestCase("clampsTo80PercentOfScreen") { t in
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let f = PinGeometry.initialFrame(imagePixelSize: CGSize(width: 4000, height: 2000),
                                         backingScale: 1, visibleFrame: vf, sourceRect: nil)
        t.approxEqual(f.width, 800)    // 80% of 1000 wide
        t.approxEqual(f.height, 400)   // aspect preserved
    },
    TestCase("staysInsideVisibleFrame") { t in
        let vf = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let f = PinGeometry.initialFrame(
            imagePixelSize: CGSize(width: 400, height: 200), backingScale: 2,
            visibleFrame: vf,
            sourceRect: CGRect(x: 1400, y: 850, width: 100, height: 50))
        t.isTrue(vf.contains(f), "frame \(f) escapes \(vf)")
    },
    TestCase("zoomScalesAroundCenter") { t in
        let current = CGRect(x: 100, y: 100, width: 200, height: 100)
        let f = PinGeometry.zoomedFrame(current: current,
                                        naturalSize: CGSize(width: 200, height: 100),
                                        factor: 2)
        t.equal(f.size, CGSize(width: 400, height: 200))
        t.approxEqual(f.midX, current.midX)
        t.approxEqual(f.midY, current.midY)
    },
    TestCase("zoomClampsToMinAndMax") { t in
        let natural = CGSize(width: 200, height: 100)
        let current = CGRect(x: 0, y: 0, width: 200, height: 100)
        let big = PinGeometry.zoomedFrame(current: current, naturalSize: natural, factor: 100)
        t.equal(big.size, CGSize(width: 600, height: 300))      // 3× cap
        let small = PinGeometry.zoomedFrame(current: current, naturalSize: natural, factor: 0.001)
        t.equal(small.size, CGSize(width: 50, height: 25))      // 0.25× floor
    },
]
