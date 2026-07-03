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
    TestCase("pinDefaults") { t in
        let s = CaptureSettings.default
        t.equal(s.pinCornerRadius, 8)
        t.isTrue(s.pinShadow)
    },
    TestCase("roundTripsPinFields") { t in
        var s = CaptureSettings.default
        s.pinCornerRadius = 0
        s.pinShadow = false
        let restored = CaptureSettings(dictionary: s.dictionary)
        t.equal(restored, s)
    },
    TestCase("historyDefaults") { t in
        let s = CaptureSettings.default
        t.isTrue(s.historyEnabled)
        t.equal(s.historyCap, 50)
    },
    TestCase("roundTripsHistoryFields") { t in
        var s = CaptureSettings.default
        s.historyEnabled = false
        s.historyCap = 100
        let restored = CaptureSettings(dictionary: s.dictionary)
        t.equal(restored, s)
    },
    TestCase("historyCapSnapsLegacyValueToAllowedSet") { t in
        let snapped = CaptureSettings(dictionary: ["historyCap": "200"])
        t.equal(snapped.historyCap, 100)
        let unchanged = CaptureSettings(dictionary: ["historyCap": "50"])
        t.equal(unchanged.historyCap, 50)
    },
    TestCase("playSoundDefaultsOnAndRoundTrips") { t in
        t.isTrue(CaptureSettings.default.playSound)
        var s = CaptureSettings.default
        s.playSound = false
        let back = CaptureSettings(dictionary: s.dictionary)
        t.isFalse(back.playSound)
    },
]
