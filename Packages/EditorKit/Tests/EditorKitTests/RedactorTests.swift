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

/// White base with 2px black vertical stripes every 4px — maximal hard edges,
/// so any working redaction must measurably destroy detail.
private func makeStripedBase() -> CGImage {
    let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    var x = 0
    while x < 100 { ctx.fill(CGRect(x: x, y: 0, width: 2, height: 100)); x += 4 }
    return ctx.makeImage()!
}

/// RGBA8 readback of an image (premultiplied-last, device RGB).
private func pixels(_ image: CGImage) -> [UInt8] {
    let w = image.width, h = image.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
        bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return buf
}

/// Number of horizontally adjacent pixel pairs whose red channels differ by
/// more than 128 — a proxy for "readable hard edges" in the region.
private func highContrastPairCount(_ image: CGImage) -> Int {
    let w = image.width, h = image.height
    let buf = pixels(image)
    var count = 0
    for y in 0..<h {
        for x in 0..<(w - 1) {
            let a = Int(buf[(y * w + x) * 4])
            let b = Int(buf[(y * w + x + 1) * 4])
            if abs(a - b) > 128 { count += 1 }
        }
    }
    return count
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
    TestCase("pixelateDestroysDetail") { t in
        let base = makeStripedBase()
        let region = CGRect(x: 10, y: 10, width: 40, height: 30)
        guard let patch = t.unwrap(Redactor.pixelate(base, region: region, blockSize: 12)),
              let original = t.unwrap(base.cropping(to: region)) else { return }
        let before = highContrastPairCount(original)
        let after = highContrastPairCount(patch)
        t.isTrue(before > 100, "striped source must start with strong edges (got \(before))")
        t.isTrue(after < before / 10, "pixelation left \(after) of \(before) hard edges")
    },
    TestCase("blurDestroysDetail") { t in
        let base = makeStripedBase()
        let region = CGRect(x: 10, y: 10, width: 40, height: 30)
        guard let patch = t.unwrap(Redactor.blur(base, region: region, radius: 12)),
              let original = t.unwrap(base.cropping(to: region)) else { return }
        let before = highContrastPairCount(original)
        let after = highContrastPairCount(patch)
        t.isTrue(before > 100, "striped source must start with strong edges (got \(before))")
        t.isTrue(after < before / 10, "blur left \(after) of \(before) hard edges")
    },
]
