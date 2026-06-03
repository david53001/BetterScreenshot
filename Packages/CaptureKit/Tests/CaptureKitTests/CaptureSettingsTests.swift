import TestKit
import Foundation
@testable import CaptureKit

let captureSettingsTests: [TestCase] = [
    TestCase("defaultsToShowOverlay") { t in
        let s = CaptureSettings.default
        t.equal(s.afterCapture, .showOverlay)
        t.equal(s.format, .png)
        t.equal(s.overlayCorner, .bottomRight)
        t.equal(s.overlayAutoDismissSeconds, 6)
    },
    TestCase("roundTripsAllFields") { t in
        var s = CaptureSettings.default
        s.afterCapture = .saveOnly
        s.format = .jpg
        s.overlayCorner = .topLeft
        s.overlayAutoDismissSeconds = 10
        let restored = CaptureSettings(dictionary: s.dictionary)
        t.equal(restored, s)
    },
]
