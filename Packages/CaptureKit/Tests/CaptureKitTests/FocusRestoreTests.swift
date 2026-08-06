import TestKit
@testable import CaptureKit

let focusRestoreTests: [TestCase] = [
    TestCase("restoresADifferentApp") { t in
        t.isTrue(FocusRestore.shouldRestore(previousBundleID: "com.apple.Safari",
                                            ownBundleID: "com.betterscreenshot.app"))
    },
    TestCase("neverRestoresOurselves") { t in
        t.isFalse(FocusRestore.shouldRestore(previousBundleID: "com.betterscreenshot.app",
                                             ownBundleID: "com.betterscreenshot.app"))
    },
    TestCase("noPreviousAppMeansNothingToRestore") { t in
        t.isFalse(FocusRestore.shouldRestore(previousBundleID: nil,
                                             ownBundleID: "com.betterscreenshot.app"))
    },
    TestCase("unknownOwnBundleStillRestores") { t in
        // Defensive: if we can't identify ourselves, handing focus back to a
        // named app is still better than stranding the user on the agent.
        t.isTrue(FocusRestore.shouldRestore(previousBundleID: "com.apple.Terminal",
                                            ownBundleID: nil))
    },
]
