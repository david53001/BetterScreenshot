import TestKit
@testable import EditorKit

let textChipTests: [TestCase] = [
    TestCase("darkChipBehindLightText") { t in t.isTrue(TextChip.chipIsDark(forTextLuminance: 0.9)) },
    TestCase("lightChipBehindDarkText") { t in t.isFalse(TextChip.chipIsDark(forTextLuminance: 0.1)) },
]
