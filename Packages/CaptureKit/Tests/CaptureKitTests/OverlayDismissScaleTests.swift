import TestKit
@testable import CaptureKit

let overlayDismissScaleTests: [TestCase] = [
    TestCase("everyStopRoundTrips") { t in
        for (position, seconds) in OverlayDismissScale.finiteStops.enumerated() {
            t.equal(OverlayDismissScale.positionToSeconds(position), seconds)
            t.equal(OverlayDismissScale.secondsToPosition(seconds), position)
        }
    },
    TestCase("stopTableSpans30SecondsTo30Minutes") { t in
        t.equal(OverlayDismissScale.finiteStops, [30, 60, 120, 300, 600, 900, 1800])
        t.equal(OverlayDismissScale.neverPosition, 7)
    },
    TestCase("positionAtOrAboveNeverIsZero") { t in
        t.equal(OverlayDismissScale.positionToSeconds(7), 0)
        t.equal(OverlayDismissScale.positionToSeconds(99), 0)
    },
    TestCase("neverRoundTrips") { t in
        t.equal(OverlayDismissScale.secondsToPosition(0), 7)
        t.equal(OverlayDismissScale.secondsToPosition(-5), 7)
    },
    TestCase("positionBelowRangeClampsToShortestStop") { t in
        t.equal(OverlayDismissScale.positionToSeconds(-1), 30)
        t.equal(OverlayDismissScale.positionToSeconds(0), 30)
    },
    TestCase("legacyValuesSnapToNearestStop") { t in
        t.equal(OverlayDismissScale.snap(6), 30)     // the pre-2.5 default
        t.equal(OverlayDismissScale.snap(1), 30)
        t.equal(OverlayDismissScale.snap(50), 60)
        t.equal(OverlayDismissScale.snap(45), 30)    // tie breaks toward the shorter stop
        t.equal(OverlayDismissScale.snap(9999), 1800)
    },
    TestCase("snapKeepsNever") { t in
        t.equal(OverlayDismissScale.snap(0), 0)
        t.equal(OverlayDismissScale.snap(-3), 0)
    },
    TestCase("snapIsIdempotentOnEveryStop") { t in
        for seconds in OverlayDismissScale.finiteStops {
            t.equal(OverlayDismissScale.snap(seconds), seconds)
        }
    },
    TestCase("labels") { t in
        t.equal(OverlayDismissScale.label(0), "Never")
        t.equal(OverlayDismissScale.label(-3), "Never")
        t.equal(OverlayDismissScale.label(30), "30s")
        t.equal(OverlayDismissScale.label(60), "1m")
        t.equal(OverlayDismissScale.label(120), "2m")
        t.equal(OverlayDismissScale.label(900), "15m")
        t.equal(OverlayDismissScale.label(1800), "30m")
    },
]
