import TestKit
import Foundation
@testable import CaptureKit

let captureSettingsTests: [TestCase] = [
    TestCase("defaults") { t in
        let s = CaptureSettings.default
        t.equal(s.afterCapture, .copyAndSave)
        t.equal(s.format, .png)
    },
    TestCase("roundTripsThroughDictionary") { t in
        var s = CaptureSettings.default
        s.afterCapture = .saveOnly
        s.format = .jpg
        let restored = CaptureSettings(dictionary: s.dictionary)
        t.equal(restored, s)
    },
]
