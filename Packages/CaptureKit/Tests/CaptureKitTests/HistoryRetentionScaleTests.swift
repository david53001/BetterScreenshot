import TestKit
import Foundation
@testable import CaptureKit

let historyRetentionScaleTests: [TestCase] = [
    TestCase("stopTableSpans10SecondsToOneHour") { t in
        t.equal(HistoryRetentionScale.finiteStops, [10, 30, 300, 600, 1800, 3600])
        t.equal(HistoryRetentionScale.neverPosition, 6)
    },
    TestCase("everyStopRoundTrips") { t in
        for (position, seconds) in HistoryRetentionScale.finiteStops.enumerated() {
            t.equal(HistoryRetentionScale.positionToSeconds(position), seconds)
            t.equal(HistoryRetentionScale.secondsToPosition(seconds), position)
        }
    },
    TestCase("neverRoundTrips") { t in
        t.equal(HistoryRetentionScale.positionToSeconds(6), 0)
        t.equal(HistoryRetentionScale.positionToSeconds(99), 0)
        t.equal(HistoryRetentionScale.secondsToPosition(0), 6)
        t.equal(HistoryRetentionScale.secondsToPosition(-5), 6)
    },
    TestCase("positionBelowRangeClampsToShortestStop") { t in
        t.equal(HistoryRetentionScale.positionToSeconds(-1), 10)
        t.equal(HistoryRetentionScale.positionToSeconds(0), 10)
    },
    TestCase("legacyValuesSnapToNearestStop") { t in
        t.equal(HistoryRetentionScale.snap(1), 10)
        t.equal(HistoryRetentionScale.snap(20), 10)      // tie breaks toward the shorter stop
        t.equal(HistoryRetentionScale.snap(21), 30)
        t.equal(HistoryRetentionScale.snap(2_592_000), 3600)  // the old hard-coded 30-day prune
    },
    TestCase("snapKeepsNever") { t in
        t.equal(HistoryRetentionScale.snap(0), 0)
        t.equal(HistoryRetentionScale.snap(-3), 0)
    },
    TestCase("labels") { t in
        t.equal(HistoryRetentionScale.label(0), "∞")
        t.equal(HistoryRetentionScale.label(10), "10s")
        t.equal(HistoryRetentionScale.label(30), "30s")
        t.equal(HistoryRetentionScale.label(300), "5m")
        t.equal(HistoryRetentionScale.label(1800), "30m")
        t.equal(HistoryRetentionScale.label(3600), "1h")
    },
    // The store takes an optional TimeInterval: nil means "keep forever".
    TestCase("maxAgeIsNilOnlyForNever") { t in
        t.isTrue(HistoryRetentionScale.maxAge(forSeconds: 0) == nil)
        t.isTrue(HistoryRetentionScale.maxAge(forSeconds: -1) == nil)
        t.equal(HistoryRetentionScale.maxAge(forSeconds: 300), TimeInterval(300))
        t.equal(HistoryRetentionScale.maxAge(forSeconds: 3600), TimeInterval(3600))
    },
]
