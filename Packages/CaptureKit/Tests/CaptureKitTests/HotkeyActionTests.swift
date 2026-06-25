import TestKit
@testable import CaptureKit

let hotkeyActionTests: [TestCase] = [
    TestCase("pauseResumeRecordingIsUnboundByDefault") { t in
        t.isTrue(HotkeyAction.allCases.contains(.pauseResumeRecording))
        t.isNil(HotkeyAction.pauseResumeRecording.defaultCombo)   // bindable, no default
        t.isFalse(HotkeyAction.pauseResumeRecording.title.isEmpty)
        t.equal(HotkeyAction.pauseResumeRecording.rawValue, "pauseResumeRecording")
    },
]
