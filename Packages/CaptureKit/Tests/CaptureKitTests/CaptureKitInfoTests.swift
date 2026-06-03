import TestKit
@testable import CaptureKit

let captureKitInfoTests: [TestCase] = [
    TestCase("versionIsSet") { t in
        t.equal(CaptureKitInfo.version, "0.1.0")
    },
]
