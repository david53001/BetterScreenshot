import TestKit
import CoreGraphics
@testable import CaptureKit

private func win(_ id: UInt32, _ frame: CGRect, layer: Int = 0, pid: pid_t = 10,
                 title: String? = nil) -> PickableWindow {
    PickableWindow(id: id, frame: frame, title: title, layer: layer, ownerPID: pid)
}

let windowPickingTests: [TestCase] = [
    TestCase("topmostReturnsFrontOnOverlap") { t in
        // Front-to-back ordered: smaller front window wins over the larger one behind.
        let front = win(1, CGRect(x: 0, y: 0, width: 100, height: 100), pid: 10)
        let back  = win(2, CGRect(x: 0, y: 0, width: 200, height: 200), pid: 11)
        t.equal(WindowPicking.topmost(at: CGPoint(x: 50, y: 50),
                                      windows: [front, back], excludingPID: 99)?.id, 1)
    },
    TestCase("skipsNonNormalLayer") { t in
        let menu = win(1, CGRect(x: 0, y: 0, width: 100, height: 100), layer: 25)   // e.g. menu/dock
        let app  = win(2, CGRect(x: 0, y: 0, width: 100, height: 100), layer: 0, pid: 11, title: "W")
        t.equal(WindowPicking.topmost(at: CGPoint(x: 10, y: 10),
                                      windows: [menu, app], excludingPID: 99)?.id, 2)
    },
    TestCase("excludesOwnPID") { t in
        let own   = win(1, CGRect(x: 0, y: 0, width: 100, height: 100), pid: 42, title: "self")
        let other = win(2, CGRect(x: 0, y: 0, width: 100, height: 100), pid: 7, title: "other")
        t.equal(WindowPicking.topmost(at: CGPoint(x: 10, y: 10),
                                      windows: [own, other], excludingPID: 42)?.id, 2)
    },
    TestCase("missReturnsNil") { t in
        let w = win(1, CGRect(x: 0, y: 0, width: 10, height: 10))
        t.isNil(WindowPicking.topmost(at: CGPoint(x: 500, y: 500),
                                      windows: [w], excludingPID: 99))
    },
    TestCase("cocoaFrameConversion") { t in
        // Primary display 900 tall; window top-left at y=100, height 200 → cocoa y = 900-100-200 = 600.
        let cocoa = WindowPicking.cocoaFrame(
            fromTopLeft: CGRect(x: 50, y: 100, width: 300, height: 200), primaryHeight: 900)
        t.equal(cocoa, CGRect(x: 50, y: 600, width: 300, height: 200))
    },
]
