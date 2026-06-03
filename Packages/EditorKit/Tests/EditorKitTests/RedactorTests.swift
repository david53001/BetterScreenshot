import TestKit
import CoreGraphics
@testable import EditorKit

private func makeBase() -> CGImage {
    let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    return ctx.makeImage()!
}

let redactorTests: [TestCase] = [
    TestCase("pixelatePatchHasRegionSize") { t in
        let region = CGRect(x: 10, y: 10, width: 40, height: 30)
        let patch = Redactor.pixelate(makeBase(), region: region, blockSize: 10)
        guard let p = t.unwrap(patch) else { return }
        t.equal(p.width, 40)
        t.equal(p.height, 30)
    },
    TestCase("blurPatchHasRegionSize") { t in
        let region = CGRect(x: 0, y: 0, width: 20, height: 20)
        let patch = Redactor.blur(makeBase(), region: region, radius: 8)
        guard let p = t.unwrap(patch) else { return }
        t.equal(p.width, 20)
        t.equal(p.height, 20)
    },
]
