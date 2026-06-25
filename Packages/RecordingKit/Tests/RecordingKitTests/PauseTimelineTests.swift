import TestKit
import CoreMedia
@testable import RecordingKit

let pauseTimelineTests: [TestCase] = [
    TestCase("zeroOffsetByDefault") { t in
        let tl = PauseTimeline()
        let p = CMTime(value: 10, timescale: 60)
        t.isTrue(tl.adjusted(p) == p)
        t.isTrue(tl.currentOffset == .zero)
    },
    TestCase("contiguousAndMonotonicAcrossOnePause") { t in
        var tl = PauseTimeline()
        let fd = CMTime(value: 1, timescale: 60)
        let lastBefore = CMTime(value: 120, timescale: 60)   // 2.0 s
        let firstAfter = CMTime(value: 360, timescale: 60)   // 6.0 s (≈4 s paused)
        tl.resume(lastPTSBeforePause: lastBefore, firstPTSAfterResume: firstAfter, frameDuration: fd)
        // No gap at the seam: adjusted(firstAfter) == lastBefore + frameDuration (in output time).
        t.approxEqual(CMTimeGetSeconds(tl.adjusted(firstAfter)),
                      CMTimeGetSeconds(lastBefore) + CMTimeGetSeconds(fd))
        // Monotonic across the seam.
        t.isTrue(CMTimeGetSeconds(tl.adjusted(firstAfter)) > CMTimeGetSeconds(tl.adjusted(lastBefore)))
    },
    TestCase("accumulatesMultiplePauses") { t in
        var tl = PauseTimeline()
        let fd = CMTime(value: 1, timescale: 60)
        tl.resume(lastPTSBeforePause: CMTime(value: 60, timescale: 60),
                  firstPTSAfterResume: CMTime(value: 180, timescale: 60), frameDuration: fd)
        let afterFirst = tl.currentOffset
        tl.resume(lastPTSBeforePause: CMTime(value: 240, timescale: 60),
                  firstPTSAfterResume: CMTime(value: 360, timescale: 60), frameDuration: fd)
        t.isTrue(CMTimeGetSeconds(tl.currentOffset) > CMTimeGetSeconds(afterFirst))
    },
    TestCase("ignoresZeroOrNegativeGap") { t in
        var tl = PauseTimeline()
        let fd = CMTime(value: 1, timescale: 60)
        // First frame after resume is exactly one frame later → gap == 0 → no offset change.
        tl.resume(lastPTSBeforePause: CMTime(value: 60, timescale: 60),
                  firstPTSAfterResume: CMTime(value: 61, timescale: 60), frameDuration: fd)
        t.isTrue(tl.currentOffset == .zero)
    },
]
