import TestKit
@testable import CaptureKit

let overlayDismissScaleTests: [TestCase] = [
    TestCase("positionToSecondsInRange") { t in
        t.equal(OverlayDismissScale.positionToSeconds(2), 2)
        t.equal(OverlayDismissScale.positionToSeconds(6), 6)
        t.equal(OverlayDismissScale.positionToSeconds(30), 30)
    },
    TestCase("positionAtOrAboveNeverIsZero") { t in
        t.equal(OverlayDismissScale.positionToSeconds(31), 0)
        t.equal(OverlayDismissScale.positionToSeconds(99), 0)
    },
    TestCase("secondsToPositionRoundTrips") { t in
        t.equal(OverlayDismissScale.secondsToPosition(2), 2)
        t.equal(OverlayDismissScale.secondsToPosition(30), 30)
        t.equal(OverlayDismissScale.secondsToPosition(0), 31)
    },
    TestCase("secondsToPositionClampsOutOfRange") { t in
        t.equal(OverlayDismissScale.secondsToPosition(1), 2)
        t.equal(OverlayDismissScale.secondsToPosition(45), 30)
    },
    TestCase("labels") { t in
        t.equal(OverlayDismissScale.label(0), "Never")
        t.equal(OverlayDismissScale.label(-3), "Never")
        t.equal(OverlayDismissScale.label(6), "6s")
        t.equal(OverlayDismissScale.label(30), "30s")
    },
]
