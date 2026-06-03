import TestKit
import Foundation
@testable import CaptureKit

let keyCodeTests: [TestCase] = [
    TestCase("digitKeyCodes") { t in
        t.equal(KeyCombo.carbonKeyCode(for: "4"), UInt32(21))
        t.equal(KeyCombo.carbonKeyCode(for: "5"), UInt32(23))
        t.equal(KeyCombo.carbonKeyCode(for: "6"), UInt32(22))
    },
    TestCase("carbonModifierMask") { t in
        // cmd+shift
        let mask = KeyCombo.carbonModifiers(command: true, shift: true,
                                            option: false, control: false)
        // cmdKey = 0x0100, shiftKey = 0x0200 → 0x0300 = 768
        t.equal(mask, UInt32(768))
    },
]
