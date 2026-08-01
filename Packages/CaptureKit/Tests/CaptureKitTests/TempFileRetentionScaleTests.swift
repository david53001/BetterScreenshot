import TestKit
import Foundation
@testable import CaptureKit

let tempFileRetentionScaleTests: [TestCase] = [
    TestCase("stopTableSpans10SecondsToOneHour") { t in
        t.equal(TempFileRetentionScale.finiteStops, [10, 30, 300, 600, 1800, 3600])
        t.equal(TempFileRetentionScale.neverPosition, 6)
    },
    TestCase("everyStopRoundTrips") { t in
        for (position, seconds) in TempFileRetentionScale.finiteStops.enumerated() {
            t.equal(TempFileRetentionScale.positionToSeconds(position), seconds)
            t.equal(TempFileRetentionScale.secondsToPosition(seconds), position)
        }
    },
    TestCase("neverRoundTrips") { t in
        t.equal(TempFileRetentionScale.positionToSeconds(6), 0)
        t.equal(TempFileRetentionScale.positionToSeconds(99), 0)
        t.equal(TempFileRetentionScale.secondsToPosition(0), 6)
        t.equal(TempFileRetentionScale.secondsToPosition(-5), 6)
    },
    TestCase("positionBelowRangeClampsToShortestStop") { t in
        t.equal(TempFileRetentionScale.positionToSeconds(-1), 10)
        t.equal(TempFileRetentionScale.positionToSeconds(0), 10)
    },
    TestCase("legacyValuesSnapToNearestStop") { t in
        t.equal(TempFileRetentionScale.snap(1), 10)
        t.equal(TempFileRetentionScale.snap(20), 10)      // tie breaks toward the shorter stop
        t.equal(TempFileRetentionScale.snap(21), 30)
        t.equal(TempFileRetentionScale.snap(2_592_000), 3600)  // the old hard-coded 30-day prune
    },
    TestCase("snapKeepsNever") { t in
        t.equal(TempFileRetentionScale.snap(0), 0)
        t.equal(TempFileRetentionScale.snap(-3), 0)
    },
    TestCase("labels") { t in
        t.equal(TempFileRetentionScale.label(0), "∞")
        t.equal(TempFileRetentionScale.label(10), "10s")
        t.equal(TempFileRetentionScale.label(30), "30s")
        t.equal(TempFileRetentionScale.label(300), "5m")
        t.equal(TempFileRetentionScale.label(1800), "30m")
        t.equal(TempFileRetentionScale.label(3600), "1h")
    },
    // The store takes an optional TimeInterval: nil means "keep forever".
    TestCase("maxAgeIsNilOnlyForNever") { t in
        t.isTrue(TempFileRetentionScale.maxAge(forSeconds: 0) == nil)
        t.isTrue(TempFileRetentionScale.maxAge(forSeconds: -1) == nil)
        t.equal(TempFileRetentionScale.maxAge(forSeconds: 300), TimeInterval(300))
        t.equal(TempFileRetentionScale.maxAge(forSeconds: 3600), TimeInterval(3600))
    },
]
