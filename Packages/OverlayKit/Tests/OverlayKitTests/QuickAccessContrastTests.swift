import TestKit
@testable import OverlayKit

let quickAccessContrastTests: [TestCase] = [
    TestCase("averageLuminanceWhiteAndBlack") { t in
        let white: [UInt8] = [255,255,255,255, 255,255,255,255]
        t.approxEqual(QuickAccessContrast.averageLuminance(rgba: white, pixelCount: 2), 1.0, tol: 0.001)
        let black: [UInt8] = [0,0,0,255, 0,0,0,255]
        t.approxEqual(QuickAccessContrast.averageLuminance(rgba: black, pixelCount: 2), 0.0, tol: 0.001)
    },
    TestCase("emptyBufferIsZero") { t in
        t.approxEqual(QuickAccessContrast.averageLuminance(rgba: [], pixelCount: 0), 0.0, tol: 0.001)
    },
    TestCase("toneThresholdBoundary") { t in
        t.equal(QuickAccessContrast.tone(forLuminance: 0.57), .light)
        t.equal(QuickAccessContrast.tone(forLuminance: 0.58), .light)
        t.equal(QuickAccessContrast.tone(forLuminance: 0.59), .dark)
    },
    TestCase("paletteForTone") { t in
        let d = QuickAccessContrast.palette(for: .dark)
        t.equal(d.glyphARGB, 0xFF18181A)
        t.equal(d.hoverARGB, 0x24000000)
        t.equal(d.pressedARGB, 0x3D000000)
        t.isTrue(d.scrimIsWhite)
        let l = QuickAccessContrast.palette(for: .light)
        t.equal(l.glyphARGB, 0xFFF4F4F6)
        t.equal(l.hoverARGB, 0x2BFFFFFF)
        t.equal(l.pressedARGB, 0x45FFFFFF)
        t.isFalse(l.scrimIsWhite)
    },
]
