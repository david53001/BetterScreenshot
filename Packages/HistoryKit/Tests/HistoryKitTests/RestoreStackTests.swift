import TestKit
import Foundation
@testable import HistoryKit

let restoreStackTests: [TestCase] = [
    TestCase("popReturnsNewestFirst") { t in
        var s = RestoreStack()
        let a = UUID(), b = UUID()
        s.push(a); s.push(b)
        t.equal(s.pop(), b)
        t.equal(s.pop(), a)
        t.isNil(s.pop())
    },
    TestCase("isEmptyTracksContents") { t in
        var s = RestoreStack()
        t.isTrue(s.isEmpty)
        s.push(UUID())
        t.isFalse(s.isEmpty)
        _ = s.pop()
        t.isTrue(s.isEmpty)
    },
    TestCase("depthCapDropsOldest") { t in
        var s = RestoreStack()
        let ids = (0..<6).map { _ in UUID() }
        for id in ids { s.push(id) }
        // ids[0] fell off the bottom; newest five remain in LIFO order.
        for id in ids.dropFirst().reversed() { t.equal(s.pop(), id) }
        t.isNil(s.pop())
    },
    TestCase("repushMovesIDToTop") { t in
        var s = RestoreStack()
        let a = UUID(), b = UUID()
        s.push(a); s.push(b); s.push(a)
        t.equal(s.pop(), a)
        t.equal(s.pop(), b)
        t.isNil(s.pop())
    },
]
