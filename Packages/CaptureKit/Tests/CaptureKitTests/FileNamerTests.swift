import TestKit
import Foundation
@testable import CaptureKit

let fileNamerTests: [TestCase] = [
    TestCase("producesDeterministicNameForFixedDate") { t in
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = DateComponents(year: 2026, month: 6, day: 2,
                                   hour: 14, minute: 32, second: 10)
        let date = cal.date(from: comps)!
        let name = FileNamer.fileName(for: date, ext: "png",
                                      timeZone: TimeZone(identifier: "UTC")!)
        t.equal(name, "Screenshot 2026-06-02 at 14.32.10.png")
    },
    TestCase("recordingPrefix") { t in
        let date = Date(timeIntervalSince1970: 0)
        let name = FileNamer.fileName(for: date, ext: "mp4", prefix: "Recording",
                                      timeZone: TimeZone(identifier: "UTC")!)
        t.equal(name, "Recording 1970-01-01 at 00.00.00.mp4")
        // Default prefix unchanged.
        t.equal(FileNamer.fileName(for: date, ext: "png",
                                   timeZone: TimeZone(identifier: "UTC")!),
                "Screenshot 1970-01-01 at 00.00.00.png")
    },
]
