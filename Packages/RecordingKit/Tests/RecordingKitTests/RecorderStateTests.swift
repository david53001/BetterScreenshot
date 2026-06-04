import TestKit
import Foundation
@testable import RecordingKit

let recorderStateTests: [TestCase] = [
    TestCase("legalTransitions") { t in
        var s = RecorderState.idle
        t.isTrue(s.transition(.arm))          // idle → armed
        t.equal(s, .armed)
        t.isTrue(s.transition(.begin(Date(timeIntervalSince1970: 100))))
        if case .recording(let started) = s {
            t.equal(started, Date(timeIntervalSince1970: 100))
        } else { t.fail("expected .recording") }
        t.isTrue(s.transition(.finish))       // recording → finishing
        t.equal(s, .finishing)
        t.isTrue(s.transition(.reset))        // finishing → idle
        t.equal(s, .idle)
    },
    TestCase("illegalTransitionsRejected") { t in
        var s = RecorderState.idle
        t.isFalse(s.transition(.finish))      // can't finish from idle
        t.equal(s, .idle)
        t.isFalse(s.transition(.begin(Date()))) // can't begin without arming
        s = .finishing
        t.isFalse(s.transition(.arm))         // busy finalizing — ⌘⇧5 ignored
        t.isFalse(s.transition(.begin(Date())))
        s = .armed
        t.isTrue(s.transition(.reset))        // cancel from the strip
        t.equal(s, .idle)
    },
    TestCase("elapsedFormatting") { t in
        let start = Date(timeIntervalSince1970: 0)
        let s = RecorderState.recording(started: start)
        t.equal(s.elapsedString(now: start.addingTimeInterval(0)), "0:00")
        t.equal(s.elapsedString(now: start.addingTimeInterval(42)), "0:42")
        t.equal(s.elapsedString(now: start.addingTimeInterval(725)), "12:05")
        t.isNil(RecorderState.idle.elapsedString(now: Date()))
    },
]
